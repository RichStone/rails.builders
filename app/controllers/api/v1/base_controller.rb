class Api::V1::BaseController < ActionController::API
  before_action :prevent_storage
  before_action :authenticate_community_member

  private

  def authenticate_community_member
    scheme, token = request.authorization.to_s.split(" ", 2)
    user = User.authenticate_community_api_token(token) if scheme&.casecmp?("Bearer")

    unless user
      response.set_header("WWW-Authenticate", 'Bearer realm="Rails Builders community API"')
      return render json: { error: "A valid community API token is required." }, status: :unauthorized
    end

    unless user.active? || user.facilitator? || user.administrator?
      return render json: { error: "Active Builder access is required." }, status: :forbidden
    end

    @current_api_user = user
  end

  def prevent_storage
    response.cache_control.replace(no_store: true)
  end
end
