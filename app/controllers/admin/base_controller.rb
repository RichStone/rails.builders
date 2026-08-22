class Admin::BaseController < ApplicationController
  before_action :require_administrator
  after_action :no_store
end
