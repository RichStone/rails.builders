class CommunityAccessTokensController < ApplicationController
  before_action :require_user

  def create
    unless session_member?
      return redirect_to dashboard_path, alert: "Active Builder access is required."
    end

    @community_api_token = current_user.issue_community_api_token!
    render :show
  end

  def destroy
    current_user.revoke_community_api_token!
    redirect_to dashboard_path, notice: "Community API token revoked."
  end
end
