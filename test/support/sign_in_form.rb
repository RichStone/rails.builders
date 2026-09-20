module SignInForm
  def sign_in_params(path: sign_in_path, **params)
    get path
    token = html_document.at_css("input[name='form_token']")["value"]
    travel 3.seconds
    { form_token: token, website: "" }.merge(params)
  end
end

ActionDispatch::IntegrationTest.include SignInForm
