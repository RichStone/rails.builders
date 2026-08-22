class EnrollmentsController < ApplicationController
  before_action :require_user

  def accept
    current_user.accept_offer!
    redirect_to dashboard_path, notice: current_user.active? ? "Your seat is confirmed." : "That offer has expired."
  end

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
    changed = current_user.update_active_membership!(active: active)

    if changed
      redirect_to dashboard_path, notice: "You released your seat."
    elsif active
      redirect_to dashboard_path, alert: "Active membership begins only by accepting a Seat Offer."
    else
      redirect_to dashboard_path, notice: "Your membership is already inactive."
    end
  end

  def join
    current_user.opt_into_waitlist!
    redirect_to dashboard_path, notice: "You’re back on the waitlist."
  end

  def waitlist
    joined = ActiveModel::Type::Boolean.new.cast(params[:joined])
    changed = current_user.update_waitlist_participation!(joined: joined)

    if changed
      redirect_to dashboard_path, notice: joined ? "You’re on the waitlist." : "You left the waitlist."
    elsif joined && !current_user.waitlisted?
      redirect_to dashboard_path, alert: "You are not currently eligible to join the waitlist."
    else
      redirect_to dashboard_path, notice: "Your waitlist choice is already up to date."
    end
  end
end
