require "openssl"

class SessionsController < ApplicationController
  NEWSLETTER_CONSENT_VERSION = "2026-08-16"

  before_action :no_store
  rate_limit to: 20, within: 5.minutes, by: -> { abuse_identity(request.remote_ip) }, name: "ip", with: -> { throttle_sign_in(:ip_rate_limit, 5.minutes) }, only: :create
  rate_limit to: 60, within: 1.hour, by: -> { abuse_identity(request.remote_ip) }, name: "ip_hour", with: -> { throttle_sign_in(:ip_rate_limit, 1.hour) }, only: :create
  rate_limit to: 150, within: 1.day, by: -> { abuse_identity(request.remote_ip) }, name: "ip_day", with: -> { throttle_sign_in(:ip_rate_limit, 1.day) }, only: :create
  before_action :reject_honeypot, only: :create
  before_action :validate_sign_in_form, only: :create
  before_action :verify_turnstile, only: :create
  rate_limit to: 5, within: 15.minutes, by: -> { abuse_identity(normalized_email) }, name: "email", with: -> { throttle_sign_in(:email_rate_limit, 15.minutes) }, only: :create
  rate_limit to: 10, within: 1.day, by: -> { abuse_identity(normalized_email) }, name: "email_day", with: -> { throttle_sign_in(:email_rate_limit, 1.day) }, only: :create

  def new
    prepare_sign_in_form
  end

  def create
    @user = User.find_or_initialize_by(email: normalized_email)
    new_registration = @user.new_record?
    if @user.valid?
      unless Rails.cache.write(mail_cooldown_key(@user.email), true, expires_in: 1.minute, unless_exist: true)
        SignupAbuse.record(:mail_cooldown)
        return redirect_to check_email_path, notice: "Check your inbox for your secure sign-in link."
      end

      @user.save!
      request_newsletter if params[:newsletter_opt_in] == "1" && @user.newsletter_confirmed_at.nil?
      token = @user.with_lock do
        @user.increment!(:sign_in_token_version)
        @user.generate_token_for(:email_verification)
      end
      UserMailer.verification(@user, token).deliver_later
      event = new_registration ? "registration_created" : "verification_link_requested"
      ProductAnalytics.capture(event)
      SignupAbuse.record(event)
      session[:development_verification_token] = token if Rails.env.development?
      redirect_to check_email_path, notice: "Check your inbox for your secure sign-in link."
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      prepare_sign_in_form
      render :new, status: :unprocessable_content
    end
  end

  def check_email
    @development_token = session.delete(:development_verification_token) if Rails.env.development?
  end

  def verification
    @token = email_link_token
    User.find_by_token_for!(:email_verification, @token)
  rescue ActionController::ParameterMissing, ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    SignupAbuse.record(:invalid_verification)
    redirect_to sign_in_path, alert: "That sign-in link is invalid or has expired. Please request a new one."
  end

  def verify
    token = email_link_token
    user = User.find_by_token_for!(:email_verification, token)
    first_verification = false
    Program.current.with_lock do
      user.with_lock do
        raise ActiveSupport::MessageVerifier::InvalidSignature unless User.find_by_token_for(:email_verification, token) == user

        first_verification = !user.verified?
        user.increment!(:sign_in_token_version)
        user.complete_verification!
      end
    end
    Rails.cache.delete(mail_cooldown_key(user.email))
    event = first_verification ? "registration_verified" : "sign_in_completed"
    ProductAnalytics.capture(event)
    SignupAbuse.record(event)
    return_to_notifications = session[:return_to_notifications]
    reset_session
    session[:user_id] = user.id
    ClickfunnelsNewsletterJob.perform_later(user.id) if user.newsletter_confirmed_at?
    redirect_to(return_to_notifications ? notification_preferences_path : dashboard_path, notice: "Email verified. Welcome to Rails Builders.")
  rescue ActionController::ParameterMissing, ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    SignupAbuse.record(:invalid_verification)
    redirect_to sign_in_path, alert: "That sign-in link is invalid or has expired. Please request a new one."
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "You’re signed out."
  end

  private

  def reject_honeypot
    return if params[:website].blank?

    SignupAbuse.record(:honeypot)
    redirect_to check_email_path, notice: "Check your inbox for your secure sign-in link."
  end

  def prepare_sign_in_form
    session[:sign_in_form_id] ||= SecureRandom.hex(16)
    @form_token = Rails.application.message_verifier(:sign_in_form).generate(
      { "id" => session[:sign_in_form_id], "started_at" => Time.current.to_f }, expires_in: 2.hours
    )
  end

  def validate_sign_in_form
    token = params[:form_token]
    form = Rails.application.message_verifier(:sign_in_form).verified(token) if token.is_a?(String) && token.bytesize <= 2048
    unless form.is_a?(Hash) && form["id"] == session[:sign_in_form_id] && form["started_at"].is_a?(Numeric)
      return reject_sign_in(:invalid_form, "This sign-in form has expired. Please try again.")
    end

    reject_sign_in(:too_fast, "Please wait a moment, then try again.") if Time.current.to_f - form["started_at"] < 2
  end

  def verify_turnstile
    case Turnstile.verify(token: params["cf-turnstile-response"], hostname: request.host)
    when :verified
      nil
    when :unavailable
      response.headers["Retry-After"] = "30"
      reject_sign_in(:turnstile_unavailable, "Browser verification is temporarily unavailable. Please try again shortly.", status: :service_unavailable)
    else
      reject_sign_in(:turnstile_rejected, "Please complete the browser verification and try again.")
    end
  end

  def reject_sign_in(reason, message, status: :unprocessable_content)
    SignupAbuse.record(reason)
    @user ||= User.new(email: normalized_email)
    flash.now[:alert] = message
    prepare_sign_in_form
    render :new, status: status
  end

  def normalized_email
    params[:email].is_a?(String) ? params[:email].strip.downcase : ""
  end

  def throttle_sign_in(reason, interval)
    response.headers["Retry-After"] = interval.to_i.to_s
    reject_sign_in(reason, "Too many sign-in requests. Please try again later or use the link already in your inbox.", status: :too_many_requests)
  end

  def abuse_identity(value)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("sign-in-rate-limits", 32), value)
  end

  def mail_cooldown_key(email)
    "sign-in-mail:#{abuse_identity(email)}"
  end

  def request_newsletter
    token = @user.with_lock do
      next if @user.newsletter_confirmed_at? || (@user.newsletter_requested_at && @user.newsletter_requested_at > 1.day.ago)

      @user.update!(
        newsletter_requested_at: Time.current,
        newsletter_consent_version: NEWSLETTER_CONSENT_VERSION,
        newsletter_requested_ip: request.remote_ip,
        newsletter_user_agent: request.user_agent.to_s.first(500),
        newsletter_token_version: @user.newsletter_token_version + 1
      )
      @user.generate_token_for(:newsletter_confirmation)
    end
    UserMailer.newsletter_confirmation(@user, token).deliver_later if token
  end
end
