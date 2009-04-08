class RepertoireCore::Users < RepertoireCore::Application

  log_params_filtered :password, :password_confirmation
    
  before :ensure_authenticated, :exclude => [:new, :validate_user, :create, :activate, :forgot_password, :password_reset_key, :reset_password ]

  #
  # Profile page.
  #
  
  # User profile display - defers to edit form
  def show(id)
    @user = User.get(id)
    raise NotFound unless @user
    display @user, :edit
  end
  
  # Show user profile page
  def edit(id)
    only_provides :html
    @user = User.get(id)
    raise NotFound unless @user
    display @user
  end
  
  # User validation web service for edit and signup forms
  def validate_user(user, id = nil)
    only_provides :json
    
    @user = id ? User.get(id) : User.new
    @user.attributes = user
    
    display @user.valid? || @user.errors_as_params
  end
  
  # Updates user profile.  Not for password changes.
  def update(id, user)
    @user = User.get(id)
    raise NotFound unless @user
    
    user[:password] = user[:password_confirmation] = nil   # close security hole by disallowing password changes
    
    if @user.update_attributes(user)
      redirect '/', :message => { :notice => "Updated your account." }
    else
      display @user, :edit
    end
  end
  
  #
  # Registration.
  #
      
  # Displays the form for user signup
  def new(user = {})
    only_provides :html
    @user = User.new(user)
    display @user
  end

  # Registers a new user and delivers the authorization email
  # TODO.  should we accept registrations to the same email so long as the account is unactivated?
  def create(user)
    @user = User.new(user)
    # validate and email activation code
    if @user.save
      @user.reload
      deliver_email(:signup, @user, {:subject => "Please Activate Your Account"}, 
                                    {:user => @user,
                                     :link => absolute_url(:activate, :activation_code => @user.activation_code) }) 
      redirect '/', :message => { :notice => "Created your account.  Please check your email." }
    else
      message[:error] = "User could not be created"
      render :new
    end
  end
  
  # Activates a user from email after registration
  def activate(activation_code)
    session.abandon!
    @user = User.first(:activation_code => activation_code)
    raise NotFound unless session.user = @user
    
    if session.authenticated? && !session.user.activated?
      User.transaction do
        session.user.activate
        deliver_email(:activation, session.user, {:subject => "Welcome"},
                                                 {:user => session.user,
                                                  :link => absolute_url(:login, :email => session.user.email)})
      end
    end
    
    redirect '/', :message => { :notice => "Your account has been activated.  Welcome to Repertoire." }
  end
  
  #
  # Password management
  #

  # Display form for resetting a user password  
  def forgot_password
    only_provides :html    
    session.abandon!
    
    render
  end
  
  # Initiates a password change by emailing reset key to user's email
  def password_reset_key(email = nil)
    session.abandon!
    if @user = User.first(:email => email)    
      User.transaction do
        @user.forgot_password!
        deliver_email(:password_reset_key, @user, {:subject => "Request to change your password"}, 
                                                  {:user => @user,
                                                   :link => absolute_url(:reset_password, :key => @user.password_reset_key)})
      end
      redirect '/', :message => { :notice => "We've emailed a link to reset your password." }
    else
      message[:error] = "Unknown user email."
      render :forgot_password
    end
  end
  
  # Change password form: either for currently logged in user, or via password reset key
  # If password reset key is provided, has the side effect of temporarily logging in user
  def reset_password(key = nil)
    only_provides :html
    @user = session.user || User.first(:password_reset_key => key)
    raise NotFound unless @user

    session.user = @user
    display @user, :reset_password
  end  
  
  # Password change validation service
  # TODO.  like the signup/login forms, insecure unless processed via https. also open to brute-force attacks
  def validate_reset_password(user, current_password = nil)
    only_provides :json

    @user = session.user
    @user.attributes = user
    msgs = {}
    
    unless @user.password_reset_key || User.authenticate(@user.email, current_password)
      msgs = { :current_password => ['Incorrect current password'] }
    end

    display (@user.valid? && msgs.empty?) || msgs.merge(@user.errors_as_params)
  end
  
  # action to update a user's password.  only allowed if user signed in via a password reset key,
  # or can confirm their own credentials
  def update_password(user = {}, current_password = nil)
    @user = session.user
    
    # make sure user changing password knows existing one or logged in via a reset key
    raise Merb::ControllerExceptions::Unauthorized unless @user.password_reset_key || User.authenticate(@user.email, current_password)

    @user.password              = user[:password]
    @user.password_confirmation = user[:password_confirmation]
  
    if @user.save
      @user.clear_forgotten_password!
      redirect '/', :message => { :notice => "Password Changed" }
    else
      message[:error] = "Password not changed: Please try again"
      render :reset_password
    end
  end
  
  #
  # Role membership
  #
  
  #
  # Implementing a full admin UI for role memberships put off until we decide on usefulness of cross-project RBAC
  #
  
  #
  # Utility functions
  #
  
  protected

  def deliver_email(action, to_user, params, send_params)
    from = Merb::Slices::config[:repertoire_core][:email_from]
    RepertoireCore::UserMailer.dispatch_and_deliver(action, params.merge(:from => from, :to => to_user.email), 
                                                    send_params)
  end
  
end