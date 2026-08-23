require "digest"

class SessionsController < ApplicationController
  NEWSLETTER_CONSENT_VERSION = "2026-08-16"

  rate_limit to: 20, within: 5.minutes, name: "ip", only: :create
  rate_limit to: 5, within: 15.minutes, by: -> { Digest::SHA256.hexdigest(normalized_email) }, name: "email", only: :create

  def new; end

  def create
    @user = User.find_or_initialize_by(email: normalized_email)
    if @user.save
      request_newsletter if params[:newsletter_opt_in] == "1" && @user.newsletter_confirmed_at.nil?
      token = @user.with_lock do
        @user.increment!(:sign_in_token_version)
        @user.generate_token_for(:email_verification)
      end
      UserMailer.verification(@user, token).deliver_later
      session[:development_verification_token] = token if Rails.env.development?
      redirect_to check_email_path, notice: "Check your inbox for your secure sign-in link."
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def check_email
    @development_token = session.delete(:development_verification_token) if Rails.env.development?
  end

  def verification
    @token = params.require(:token)
    User.find_by_token_for!(:email_verification, @token)
  rescue ActionController::ParameterMissing, ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to sign_in_path, alert: "That sign-in link is invalid or has expired. Please request a new one."
  end

  def verify
    user = User.find_by_token_for!(:email_verification, params.require(:token))
    user.with_lock do
      raise ActiveSupport::MessageVerifier::InvalidSignature unless User.find_by_token_for(:email_verification, params[:token]) == user

      user.increment!(:sign_in_token_version)
    end
    user.complete_verification!
    reset_session
    session[:user_id] = user.id
    ClickfunnelsNewsletterJob.perform_later(user.id) if user.newsletter_confirmed_at?
    redirect_to dashboard_path, notice: "Email verified. Welcome to Rails Builders."
  rescue ActionController::ParameterMissing, ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to sign_in_path, alert: "That sign-in link is invalid or has expired. Please request a new one."
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "You’re signed out."
  end

  private

  def normalized_email
    params[:email].to_s.strip.downcase
  end

  def request_newsletter
    token = @user.with_lock do
      @user.update!(
        newsletter_requested_at: Time.current,
        newsletter_consent_version: NEWSLETTER_CONSENT_VERSION,
        newsletter_requested_ip: request.remote_ip,
        newsletter_user_agent: request.user_agent.to_s.first(500),
        newsletter_token_version: @user.newsletter_token_version + 1
      )
      @user.generate_token_for(:newsletter_confirmation)
    end
    UserMailer.newsletter_confirmation(@user, token).deliver_later
  end
end
