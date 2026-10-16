class Admin::BaseController < ApplicationController
  before_action :require_administrator
  before_action :require_recent_authentication, unless: -> { request.get? || request.head? }
end
