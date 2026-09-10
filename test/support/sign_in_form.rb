module SignInForm
  def sign_in_params(**params)
    get sign_in_path
    token = html_document.at_css("input[name='form_token']")["value"]
    travel 3.seconds
    { form_token: token, website: "" }.merge(params)
  end
end

ActionDispatch::IntegrationTest.include SignInForm
