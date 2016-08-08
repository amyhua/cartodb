require_relative '../../../../spec_helper'
require_relative '../../../../factories/users_helper'

describe Carto::Builder::Public::EmbedsController do
  include_context 'users helper'
  include Warden::Test::Helpers

  before(:all) do
    @user = FactoryGirl.create(:valid_user)
    @map = FactoryGirl.create(:map, user_id: @user.id)
    @visualization = FactoryGirl.create(:carto_visualization, user_id: @user.id, map_id: @map.id)
  end

  before(:each) do
    Carto::Visualization.any_instance.stubs(:organization?).returns(false)
    Carto::Visualization.any_instance.stubs(:get_auth_tokens).returns(['trusty_token'])
  end

  after(:all) do
    @map.destroy
    @visualization.destroy
    @user.destroy
  end

  describe '#show' do
    it 'embeds visualizations' do
      get builder_visualization_public_embed_url(visualization_id: @visualization.id)

      response.status.should == 200
      response.body.include?(@visualization.name).should be true
    end

    it 'defaults to generate vizjson with vector=false' do
      get builder_visualization_public_embed_url(visualization_id: @visualization.id)

      response.status.should == 200
      response.body.should include('\"vector\":false')
    end

    it 'generates vizjson with vector=true with flag' do
      get builder_visualization_public_embed_url(visualization_id: @visualization.id, vector: true)

      response.status.should == 200
      response.body.should include('\"vector\":true')
    end

    it 'does not include auth tokens for public/link visualizations' do
      get builder_visualization_public_embed_url(visualization_id: @visualization.id, vector: true)

      response.status.should == 200
      response.body.should include("var authTokens = JSON.parse('null');")
    end

    it 'does not embed private visualizations' do
      @visualization.privacy = Carto::Visualization::PRIVACY_PRIVATE
      @visualization.save

      get builder_visualization_public_embed_url(visualization_id: @visualization.id)

      response.body.include?('Embed error | CARTO').should be true
      response.status.should == 403
    end

    it 'does not embed password protected viz' do
      @visualization.privacy = Carto::Visualization::PRIVACY_PROTECTED
      @visualization.save

      get builder_visualization_public_embed_url(visualization_id: @visualization.id)

      response.body.include?('Protected map').should be true
      response.status.should == 403
    end

    it 'returns 404 for inexistent visualizations' do
      get builder_visualization_public_embed_url(visualization_id: UUIDTools::UUID.timestamp_create.to_s)

      response.status.should == 404
    end

    it 'includes auth tokens for privately shared visualizations' do
      @visualization.privacy = Carto::Visualization::PRIVACY_PRIVATE
      @visualization.save

      Carto::Visualization.any_instance.stubs(:organization?).returns(true)

      login_as(@user)
      get builder_visualization_public_embed_url(visualization_id: @visualization.id, vector: true)

      response.status.should == 200
      @user.reload
      @user.get_auth_tokens.each { |token| response.body.should include token }
    end
  end

  describe '#show_protected' do
    it 'rejects incorrect passwords' do
      @visualization.privacy = Carto::Visualization::PRIVACY_PROTECTED
      @visualization.save

      Carto::Visualization.any_instance.stubs(:has_password?).returns(true)
      Carto::Visualization.any_instance.stubs(:password_valid?).with('manolo').returns(false)

      post builder_visualization_public_embed_protected_url(visualization_id: @visualization.id, password: 'manolo')

      response.body.include?('The password is not ok').should be true
      response.status.should == 403
    end

    it 'accepts correct passwords' do
      @visualization.privacy = Carto::Visualization::PRIVACY_PROTECTED
      @visualization.save

      Carto::Visualization.any_instance.stubs(:has_password?).returns(true)
      Carto::Visualization.any_instance.stubs(:password_valid?).with('manolo').returns(true)

      post builder_visualization_public_embed_protected_url(visualization_id: @visualization.id, password: 'manolo')

      response.body.include?('The password is not ok').should_not be true
      response.body.include?(@visualization.name).should be true
      response.status.should == 200
    end

    it 'includes auth tokens' do
      @visualization.privacy = Carto::Visualization::PRIVACY_PROTECTED
      @visualization.save

      Carto::Visualization.any_instance.stubs(:has_password?).returns(true)
      Carto::Visualization.any_instance.stubs(:password_valid?).with('manolo').returns(true)

      post builder_visualization_public_embed_protected_url(visualization_id: @visualization.id, password: 'manolo')

      response.status.should == 200
      @visualization.get_auth_tokens.each { |token| response.body.should include token }
    end
  end
end
