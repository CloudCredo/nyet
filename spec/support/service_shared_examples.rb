shared_examples_for "A bindable service" do |app_name|
  let(:user) { RegularUser.from_env }
  let!(:org) { user.find_organization_by_name(ENV.fetch("NYET_ORGANIZATION_NAME")) }
  let!(:space) { user.create_space(org) }
  let(:dog_tags) { {service: app_name} }

  after do
    monitoring.record_action(:delete, dog_tags) do
      space.delete!(:recursive => true)
    end
  end

  it "allows users to create, bind, read, write, unbind, and delete the #{app_name} service" do
    plan = user.find_service_plan(service_name, plan_name)
    plan.should be

    service_instance = nil
    binding = nil
    test_app = nil

    app = user.create_app(space, app_name)
    route = user.create_route(app, "#{app_name}-#{SecureRandom.hex(2)}")

    begin
      monitoring.record_action("create_service", dog_tags) do
        service_instance = user.create_service_instance(space, service_name, plan_name)
        service_instance.guid.should be
      end

      monitoring.record_action("bind_service", dog_tags) do
        binding = user.bind_service_to_app(service_instance, app)
        binding.guid.should be
      end

      app.upload(File.expand_path("../../../apps/ruby/app_sinatra_service", __FILE__))
      monitoring.record_action(:start, dog_tags) do
        app.start!(true)
        test_app = TestApp.new(app, route.name, service_instance, namespace)
        test_app.when_running
      end

      test_app.get_env

      test_app.insert_value('key', 'value').should be_a Net::HTTPSuccess
      test_app.get_value('key').should == 'value'
      monitoring.record_metric("health", 1, dog_tags)
    rescue => e
      monitoring.record_metric("health", 0, dog_tags)
      raise e
    end

    binding.delete!
    service_instance.delete!
    app.delete!
  end
end