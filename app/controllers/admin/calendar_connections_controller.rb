class Admin::CalendarConnectionsController < Admin::BaseController
  before_action :set_program
  before_action :set_connection, except: :create

  def show
    @calendars = calendar_client.owned_secondary_calendars
  rescue StandardError => error
    record_connection_error(error)
    redirect_to admin_root_path, alert: "Google Calendar could not be reached. Reconnect it and try again."
  end

  def create
    facilitator = @program.main_facilitator
    return redirect_to(admin_root_path, alert: "Assign a main facilitator before connecting Google Calendar.") unless facilitator
    if @program.calendar_connection && @program.calendar_credentials_in_use?
      return redirect_to admin_root_path,
        alert: "Wait for the live session and automatic transcript import to finish before reconnecting Google Calendar."
    end

    replace_connection_for(facilitator)
    code_verifier = GoogleWorkspace::Authorization.generate_code_verifier
    session[:google_oauth_code_verifier] = code_verifier
    url = authorization(code_verifier:).authorization_url(
      request:,
      redirect_to: admin_calendar_connection_path,
      login_hint: facilitator.email
    )
    redirect_to url, allow_other_host: true
  rescue StandardError => error
    session.delete(:google_oauth_code_verifier)
    record_connection_error(error)
    redirect_to admin_root_path, alert: "Google Calendar authorization could not be started."
  end

  def callback
    code_verifier = session.delete(:google_oauth_code_verifier)
    raise ArgumentError, "Missing OAuth verifier" if code_verifier.blank?

    authorizer = authorization(code_verifier:)
    authorizer.authorize!(request)
    account_email = GoogleWorkspace::CalendarClient.new(
      connection: @connection,
      credentials: authorizer.credentials
    ).account_email.to_s.downcase

    unless ActiveSupport::SecurityUtils.secure_compare(account_email, @connection.facilitator.email.downcase)
      authorizer.revoke!
      @connection.update!(
        oauth_token_json: "{}",
        status: "reauthorization_required",
        last_error_code: "account_mismatch"
      )
      return redirect_to(admin_root_path, alert: "Connect the main facilitator’s Google account.")
    end

    @connection.update!(google_account_email: account_email, status: "authorizing", last_error_code: nil)
    redirect_to admin_calendar_connection_path, notice: "Google account connected. Choose the Sessions calendar."
  rescue StandardError => error
    record_connection_error(error)
    redirect_to admin_root_path, alert: "Google Calendar authorization failed. Please reconnect it."
  end

  def update
    calendar = calendar_client.owned_secondary_calendars.find { |candidate| candidate.fetch(:id) == params[:calendar_id] }
    raise ActiveRecord::RecordNotFound unless calendar
    raise ActiveRecord::RecordNotFound unless calendar.fetch(:data_owner, "").casecmp?(@connection.google_account_email)

    @connection.update!(
      google_calendar_id: calendar.fetch(:id),
      google_calendar_name: calendar.fetch(:name),
      google_calendar_time_zone: calendar[:time_zone],
      google_data_owner: calendar.fetch(:data_owner),
      status: "connected",
      last_error_code: nil
    )
    GoogleCalendarSyncJob.perform_later(@connection.id)
    redirect_to admin_root_path, notice: "Sessions calendar connected. The first sync is queued."
  rescue StandardError => error
    record_connection_error(error)
    redirect_to admin_calendar_connection_path, alert: "Choose a secondary calendar owned by the main facilitator."
  end

  def sync
    return redirect_to(admin_root_path, alert: "Reconnect Google Calendar before syncing.") unless @connection.status == "connected"

    GoogleCalendarSyncJob.perform_later(@connection.id)
    redirect_to admin_root_path, notice: "Calendar sync queued."
  end

  def destroy
    if @program.calendar_credentials_in_use?
      return redirect_to admin_root_path,
        alert: "Wait for the live session and automatic transcript import to finish before disconnecting Google Calendar."
    end

    begin
      authorization.revoke!
    rescue StandardError => error
      Rails.logger.warn("Google Calendar token revocation failed (#{error.class.name})")
    end
    @connection.destroy!
    redirect_to admin_root_path, notice: "Google Calendar disconnected."
  end

  private

  def set_program
    @program = Program.current
  end

  def set_connection
    @connection = @program.calendar_connection
    redirect_to(admin_root_path, alert: "Connect Google Calendar first.") unless @connection
  end

  def replace_connection_for(facilitator)
    existing = @program.calendar_connection
    if existing
      begin
        authorization(connection: existing).revoke!
      rescue StandardError => error
        Rails.logger.warn("Old Google Calendar token revocation failed (#{error.class.name})")
      end
    end
    if existing && existing.facilitator != facilitator
      existing.destroy!
      existing = nil
    end

    @connection = existing || @program.build_calendar_connection
    @connection.assign_attributes(
      facilitator:,
      google_account_email: facilitator.email,
      google_calendar_id: "pending",
      google_calendar_name: "Pending authorization",
      google_calendar_time_zone: nil,
      google_data_owner: nil,
      oauth_token_json: "{}",
      status: "authorizing",
      last_synced_at: nil,
      last_error_code: nil
    )
    @connection.save!
  end

  def authorization(connection: @connection, code_verifier: nil)
    GoogleWorkspace::Authorization.new(
      connection:,
      callback_uri: google_callback_uri,
      code_verifier:
    )
  end

  def google_callback_uri
    return callback_admin_calendar_connection_url unless Rails.env.production?

    callback_admin_calendar_connection_url(
      host: ENV.fetch("APP_HOST", "rails.builders"),
      protocol: "https"
    )
  end

  def calendar_client
    GoogleWorkspace::CalendarClient.new(connection: @connection)
  end

  def record_connection_error(error)
    Rails.logger.warn("Google Calendar operation failed (#{error.class.name})")
    @connection&.update_columns(
      status: @connection.status == "authorizing" ? "reauthorization_required" : "error",
      last_error_code: error.class.name.first(100),
      updated_at: Time.current
    )
  end
end
