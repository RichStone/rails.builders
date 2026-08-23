class AddReadinessPointsToPrograms < ActiveRecord::Migration[8.1]
  READINESS_POINTS = <<~TEXT.strip
    You have the ONE product you would hack on with us.
    You have a concrete offer you can put into one sentence for that product.
    You use AI heavily to build it and are excited to share how you do it.
    You use Rails to support your product in one way or another.
    You have a funnel for that product.
    You have a checkout (so it's purchaseable).
  TEXT

  def change
    add_column :programs, :readiness_points, :text, null: false, default: READINESS_POINTS
  end
end
