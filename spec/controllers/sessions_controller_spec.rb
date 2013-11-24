require 'spec_helper'

describe SessionsController do
  context 'github' do
    before :each do
      request.env['omniauth.auth'] = YAML.load_file 'spec/fixtures/oauth/github.yml'
    end

    it 'creates from github' do
      VCR.use_cassette 'github-gravatar' do
        get :create, provider: 'github'
      end
      controller.send(:current_user).should be_present
      Owner.first.tap do |owner|
        owner.identities.first.email.should == 'info@stefanwienert.de'
        owner.identities.first.image.should be_present
      end
    end

    it 'relogins' do

      VCR.use_cassette 'github-gravatar' do
        get :create, provider: 'github'
      end

      session[:owner_id] = nil
      get :create, provider: 'github'
      Owner.count.should == 1
      Identity.count.should == 1
      session[:owner_id].should == Owner.first.id
    end

    it 'merges accounts' do
      old = Owner.create
      session[:owner_id] = old.id

      VCR.use_cassette 'github-gravatar' do
        get :create,  provider: 'github'
      end

      Owner.count.should == 1
      Owner.first.token.should be_nil
      Identity.count.should == 1
      session[:owner_id].should == old.id
    end

  end
end