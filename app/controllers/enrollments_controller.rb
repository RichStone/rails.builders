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

  def join
    current_user.opt_into_waitlist!
    redirect_to dashboard_path, notice: "You’re back on the waitlist."
  end
end
