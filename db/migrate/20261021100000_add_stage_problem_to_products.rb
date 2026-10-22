class AddStageProblemToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :stage_problem, :string
    add_column :products, :stage_problem_analysis, :text
  end
end
