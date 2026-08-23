class EnrollmentsController < ApplicationController
  before_action :require_user

  def decline
    current_user.decline_offer!
    redirect_to dashboard_path, notice: "You declined the offer. You can join the waitlist again anytime."
  end

  def withdraw
    current_user.withdraw_seat!
    redirect_to dashboard_path, notice: "You released your seat."
  end

  def membership
    active = ActiveModel::Type::Boolean.new.cast(params[:active])
    changed = current_user.update_active_membership!(active:, readiness: params[:readiness])

    if changed
      redirect_to dashboard_path, notice: active ? "You’re confirmed as an Active Builder." : "You released your seat."
    elsif active && current_user.offered?
      redirect_to dashboard_path, alert: "Check off every readiness point before marking yourself active."
    elsif active && current_user.enrollment_status == "expired"
      redirect_to dashboard_path, alert: "That offer has expired."
    elsif active
      redirect_to dashboard_path, alert: "Active Builder status is available only while you have a Seat Offer."
    else
      redirect_to dashboard_path, notice: "Your membership is already inactive."
    end
  end

  def waitlist
    joined = ActiveModel::Type::Boolean.new.cast(params[:joined])
    changed = current_user.update_waitlist_participation!(joined:, readiness: params[:readiness])

    if changed
      current_user.reload if joined
      notice = if current_user.offered?
        "Your turn is open. Complete the readiness check to confirm your Seat."
      elsif joined
        "You’re on the waitlist."
      else
        "You left the waitlist."
      end
      redirect_to dashboard_path, notice:
    elsif joined && current_user.waitlist_eligible? && !Program.current.readiness_confirmed?(params[:readiness])
      redirect_to dashboard_path, alert: "Check off every readiness point before joining the waitlist."
    elsif joined && !current_user.waitlisted?
      redirect_to dashboard_path, alert: "You are not currently eligible to join the waitlist."
    else
      redirect_to dashboard_path, notice: "Your waitlist choice is already up to date."
    end
  end
end
