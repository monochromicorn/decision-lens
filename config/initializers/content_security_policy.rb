# Strict CSP: everything is first-party (Pico CSS is vendored, no inline scripts/styles).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self
    policy.img_src    :self, :data
    policy.font_src    :self
    policy.connect_src :self
    policy.object_src  :none
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :none
  end
end
