class Api::V1::CommunityController < Api::V1::BaseController
  def show
    render json: CommunitySnapshot.new(
      program: Program.current,
      generated_at: Time.current,
      avatar_url: method(:avatar_url)
    ).as_json
  end

  private

  def avatar_url(builder)
    return unless builder.avatar.attached?

    url_for(builder.avatar.variant(resize_to_limit: [ 640, 640 ], saver: { strip: true }))
  end
end
