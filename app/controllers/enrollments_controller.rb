class EnrollmentsController < ApplicationController
  before_action :require_user

  def decline
    current_user.decline_offer!
    redirect_to dashboard_path, notice: "You canceled your request. You can request to join Builders again anytime."
  end

  def withdraw
    current_user.withdraw_seat!
    redirect_to dashboard_path, notice: "You released your seat."
  end

  def membership
    active = ActiveModel::Type::Boolean.new.cast(params[:active])
    changed = current_user.update_active_membership!(active:)

    if changed
      redirect_to dashboard_path, notice: "You released your seat."
    elsif active
      redirect_to dashboard_path, alert: "An admin or facilitator will confirm your place. Give us a few days at most."
    else
      redirect_to dashboard_path, notice: "Your membership is already inactive."
    end
  end

  def waitlist
    joined = ActiveModel::Type::Boolean.new.cast(params[:joined])
    changed = current_user.update_waitlist_participation!(joined:, readiness: params[:readiness])

    if changed
      current_user.reload if joined
      notice = joined ? "Your request is with the team. Give us a few days at most to confirm your place." : "You left the waitlist."
      redirect_to dashboard_path, notice:
    elsif joined && current_user.waitlist_eligible? && !Program.current.readiness_confirmed?(params[:readiness])
      redirect_to dashboard_path, alert: "Check off every readiness point before joining the waitlist."
    elsif joined && !current_user.waitlisted? && !current_user.offered?
      redirect_to dashboard_path, alert: "You are not currently eligible to join the waitlist."
    else
      redirect_to dashboard_path, notice: "Your join request is already up to date."
    end
  end
end
