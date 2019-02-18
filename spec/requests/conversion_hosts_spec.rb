describe "ConversionHosts API" do
  before(:all) do
    NotificationType.seed
  end

  context "collections" do
    it 'lists all conversion hosts with an appropriate role' do
      conversion_host = FactoryBot.create(:conversion_host, :resource => FactoryBot.create(:vm_openstack))
      api_basic_authorize(collection_action_identifier(:conversion_hosts, :read, :get))
      get(api_conversion_hosts_url)

      expected = {
        'count'     => 1,
        'name'      => 'conversion_hosts',
        'resources' => [
          hash_including('href' => api_conversion_host_url(nil, conversion_host))
        ]
      }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(expected)
    end
  end

  context "resources" do
    it 'will show a conversion host with an appropriate role' do
      conversion_host = FactoryBot.create(:conversion_host, :resource => FactoryBot.create(:vm_openstack))
      api_basic_authorize(action_identifier(:conversion_hosts, :read, :resource_actions, :get))

      get(api_conversion_host_url(nil, conversion_host))

      expect(response.parsed_body).to include('href' => api_conversion_host_url(nil, conversion_host))
      expect(response).to have_http_status(:ok)
    end
  end

  context "access" do
    it "forbids access to conversion hosts without an appropriate role" do
      api_basic_authorize
      get(api_conversion_hosts_url)

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids access to a conversion host resource without an appropriate role" do
      api_basic_authorize
      conversion_host = FactoryBot.create(:conversion_host, :resource => FactoryBot.create(:vm_openstack))
      get(api_conversion_host_url(nil, conversion_host))

      expect(response).to have_http_status(:forbidden)
    end
  end

  context "create" do
    let(:zone) { FactoryBot.create(:zone) }
    let(:ems_openstack) { FactoryBot.create(:ems_openstack, :zone => zone) }
    let(:ems_redhat) { FactoryBot.create(:ems_redhat, :zone => zone) }
    let(:vm) { FactoryBot.create(:vm_openstack, :ext_management_system => ems_openstack) }
    let(:host) { FactoryBot.create(:host_redhat, :ext_management_system => ems_redhat) }

    let(:sample_conversion_host_from_vm) do
      {
        :name          => "test_conversion_host_from_vm",
        :resource_type => vm.type,
        :resource_id   => vm.id,
        :version       => "1.0"
      }
    end

    let(:sample_conversion_host_from_host) do
      {
        :name          => "test_conversion_host_from_host",
        :resource_type => host.type,
        :resource_id   => host.id,
        :version       => "1.0"
      }
    end

    let(:expected_attributes) { %w(id name resource_type resource_id version) }

    it "raises an error if an invalid resource type is provided" do
      api_basic_authorize(collection_action_identifier(:conversion_hosts, :create))
      sample_conversion_host_from_vm['resource_type'] = 'bogus'
      post(api_conversion_hosts_url, :params => sample_conversion_host_from_vm)

      expect(response).to have_http_status(400)

      results = response.parsed_body
      expect(results['error']['kind']).to eql('bad_request')
      expect(results['error']['message']).to eql('invalid resource_type bogus')
    end

    it "supports single conversion host creation" do
      api_basic_authorize(collection_action_identifier(:conversion_hosts, :create))

      post(api_conversion_hosts_url, :params => sample_conversion_host_from_vm)

      expect(response).to have_http_status(:ok)

      results = response.parsed_body["results"].first
      task_id = results['task_id']

      expect(task_id).to match(/\d+/)
      expect(MiqTask.exists?(task_id.to_i)).to be_truthy

      expect(results).to include(
        'success'   => true,
        'href'      => 'http://www.example.com/api/conversion_hosts/',
        'message'   => "Enabling resource id:#{vm.id} type:#{vm.class}",
        'task_id'   => task_id,
        'task_href' => "http://www.example.com/api/tasks/#{task_id}"
      )
    end

    it "supports multiple conversion host creation" do
      api_basic_authorize(collection_action_identifier(:conversion_hosts, :create))

      conversion_hosts = [sample_conversion_host_from_vm, sample_conversion_host_from_host]
      post(api_conversion_hosts_url, :params => gen_request(:create, conversion_hosts))

      expect(response).to have_http_status(:ok)

      results = response.parsed_body["results"]

      expect(results).to contain_exactly(
        a_hash_including("message" => "Enabling resource id:#{vm.id} type:#{vm.class}", "task_id" => a_kind_of(String)),
        a_hash_including("message" => "Enabling resource id:#{host.id} type:#{host.class}", "task_id" => a_kind_of(String)),
      )
    end
  end

  context "disable" do
    let(:zone) { FactoryBot.create(:zone) }
    let(:ems) { FactoryBot.create(:ems_openstack, :zone => zone) }
    let(:vm) { FactoryBot.create(:vm_openstack, :ext_management_system => ems) }
    let(:conversion_host) { FactoryBot.create(:conversion_host, :resource => vm) }
    let(:conversion_host_url) { api_conversion_host_url(nil, conversion_host) }

    before do
      allow(conversion_host).to receive(:install_conversion_host_module).and_return(true)
      allow(conversion_host).to receive(:resource_search).and_return(vm)
      allow(conversion_host).to receive(:ansible_playbook).and_return({})
    end

    it "can disable a resource via POST" do
      api_basic_authorize(action_identifier(:conversion_hosts, :disable, :resource_actions))
      allow(conversion_host).to receive(:check_conversion_host_role).and_return('disabled')

      post(conversion_host_url, :params => {"action" => "disable"})

      expect(response).to have_http_status(:ok)

      results = response.parsed_body
      task_id = results['task_id']

      expect(task_id).to match(/\d+/)
      expect(MiqTask.exists?(task_id.to_i)).to be_truthy

      expect(results).to include(
        'success'   => true,
        'href'      => "http://www.example.com/api/conversion_hosts/#{conversion_host.id}",
        'message'   => "Disabling ConversionHost id:#{conversion_host.id} name:#{conversion_host.name}",
        'task_id'   => task_id,
        'task_href' => "http://www.example.com/api/tasks/#{task_id}"
      )
    end
  end

  context "delete" do
    let(:zone)                        { FactoryBot.create(:zone) }
    let(:ems)                         { FactoryBot.create(:ems_openstack, :zone => zone) }
    let(:vm)                          { FactoryBot.create(:vm_openstack, :ext_management_system => ems) }
    let(:vm2)                         { FactoryBot.create(:vm_openstack, :ext_management_system => ems) }
    let(:conversion_host)             { FactoryBot.create(:conversion_host, :resource => vm) }
    let(:conversion_host_url)         { api_conversion_host_url(nil, conversion_host) }
    let(:invalid_conversion_host_url) { api_conversion_host_url(nil, 999_999) }

    it "can delete a conversion host via DELETE" do
      api_basic_authorize(action_identifier(:conversion_hosts, :delete))
      delete(conversion_host_url)

      expect(response).to have_http_status(:no_content)
    end

    it "can delete a conversion host via POST" do
      api_basic_authorize(action_identifier(:conversion_hosts, :delete, :resource_actions))
      post(conversion_host_url, :params => gen_request(:delete))

      results = response.parsed_body
      task_id = results['task_id']

      expect(task_id).to match(/\d+/)
      expect(MiqTask.exists?(task_id.to_i)).to be_truthy

      expect(results).to include(
        'success'   => true,
        'message'   => "Disabling ConversionHost id:#{conversion_host.id} name:#{conversion_host.name}",
        'task_id'   => task_id,
        'task_href' => "http://www.example.com/api/tasks/#{task_id}"
      )
    end

    it "will not delete a conversion host unless authorized" do
      api_basic_authorize
      delete(conversion_host_url)

      expect(response).to have_http_status(:forbidden)
      expect(ConversionHost.exists?(conversion_host.id)).to be_truthy
    end

    it "can delete multiple conversion hosts" do
      api_basic_authorize(collection_action_identifier(:conversion_hosts, :delete))
      chost1 = FactoryBot.create(:conversion_host, :resource => vm)
      chost2 = FactoryBot.create(:conversion_host, :resource => vm2)

      chost1_id, chost2_id = chost1.id, chost2.id
      chost1_url = api_conversion_host_url(nil, chost1_id)
      chost2_url = api_conversion_host_url(nil, chost2_id)

      post(api_conversion_hosts_url, :params => gen_request(:delete, [{"href" => chost1_url}, {"href" => chost2_url}]))
      expect_multiple_action_result(2)

      results = response.parsed_body['results']
      task_one_id = results.first['task_id']
      task_two_id = results.last['task_id']

      expect(MiqTask.exists?(task_one_id.to_i)).to be_truthy
      expect(MiqTask.exists?(task_two_id.to_i)).to be_truthy

      expect(results).to contain_exactly(
        a_hash_including(
          'success'   => true,
          'message'   => "Disabling ConversionHost id:#{chost1.id} name:#{chost1.name}",
          'task_id'   => task_one_id,
          'task_href' => "http://www.example.com/api/tasks/#{task_one_id}"
        ),
        a_hash_including(
          'success'   => true,
          'message'   => "Disabling ConversionHost id:#{chost2.id} name:#{chost2.name}",
          'task_id'   => task_two_id,
          'task_href' => "http://www.example.com/api/tasks/#{task_two_id}"
        )
      )
    end
  end

  context "tags" do
    let(:tag1) { {:category => "department", :name => "finance", :path => "/managed/department/finance"} }
    let(:tag2) { {:category => "cc",         :name => "001",     :path => "/managed/cc/001"} }
    let(:vm)   { FactoryBot.create(:vm_openstack) }

    let(:invalid_tag_url) { api_tag_url(nil, 999_999) }

    let(:conversion_host) { FactoryBot.create(:conversion_host, :resource => vm, :name => 'conversion_host_with_tags') }

    before do
      FactoryBot.create(:classification_department_with_tags)
      FactoryBot.create(:classification_cost_center_with_tags)
    end

    it "can list the tags for a conversion host" do
      Classification.classify(conversion_host, tag1[:category], tag1[:name])
      api_basic_authorize
      get(api_conversion_host_tags_url(nil, conversion_host))

      expect(response.parsed_body).to include("subcount" => 1)
      expect(response).to have_http_status(:ok)
    end

    it "can assign a tag to a conversion host" do
      api_basic_authorize(subcollection_action_identifier(:conversion_hosts, :tags, :assign))

      post(api_conversion_host_tags_url(nil, conversion_host), :params => { :action => "assign", :category => "department", :name => "finance" })

      expected = {
        "results" => [
          a_hash_including(
            "success"      => true,
            "message"      => a_string_matching(/assigning tag/i),
            "tag_category" => "department",
            "tag_name"     => "finance"
          )
        ]
      }
      expect(response.parsed_body).to include(expected)
      expect(response).to have_http_status(:ok)

      tag = Tag.find_by(:name => '/managed/department/finance')
      expect(tag).to be_truthy
      expect(ConversionHost.find_by(:name => 'conversion_host_with_tags').tags).to include(tag)
    end

    it "can unassign a tag from a conversion host" do
      Classification.classify(conversion_host, tag1[:category], tag1[:name])
      api_basic_authorize(subcollection_action_identifier(:conversion_hosts, :tags, :unassign))

      post(api_conversion_host_tags_url(nil, conversion_host), :params => { :action => "unassign", :category => "department", :name => "finance" })

      expected = {
        "results" => [
          a_hash_including(
            "success"      => true,
            "message"      => a_string_matching(/unassigning tag/i),
            "tag_category" => "department",
            "tag_name"     => "finance"
          )
        ]
      }
      expect(response.parsed_body).to include(expected)
      expect(response).to have_http_status(:ok)
    end

    it "assigns multiple tags to a conversion_host" do
      api_basic_authorize subcollection_action_identifier(:conversion_hosts, :tags, :assign)

      post(api_conversion_host_tags_url(nil, conversion_host), :params => gen_request(:assign, [{:name => tag1[:path]}, {:name => tag2[:path]}]))

      expect_tagging_result(
        [{:success => true, :href => api_conversion_host_url(nil, conversion_host), :tag_category => tag1[:category], :tag_name => tag1[:name]},
         {:success => true, :href => api_conversion_host_url(nil, conversion_host), :tag_category => tag2[:category], :tag_name => tag2[:name]}]
      )
    end

    it "assigns tags by mixed specification to a conversion_host" do
      api_basic_authorize subcollection_action_identifier(:conversion_hosts, :tags, :assign)

      tag = Tag.find_by(:name => tag2[:path])
      post(api_conversion_host_tags_url(nil, conversion_host), :params => gen_request(:assign, [{:name => tag1[:path]}, {:href => api_tag_url(nil, tag)}]))

      expect_tagging_result(
        [{:success => true, :href => api_conversion_host_url(nil, conversion_host), :tag_category => tag1[:category], :tag_name => tag1[:name]},
         {:success => true, :href => api_conversion_host_url(nil, conversion_host), :tag_category => tag2[:category], :tag_name => tag2[:name]}]
      )
    end

    it "unassigns multiple tags from a conversion_host" do
      Classification.classify(conversion_host, tag2[:category], tag2[:name])

      api_basic_authorize subcollection_action_identifier(:conversion_hosts, :tags, :unassign)

      tag = Tag.find_by(:name => tag2[:path])
      post(api_conversion_host_tags_url(nil, conversion_host), :params => gen_request(:unassign, [{:name => tag1[:path]}, {:href => api_tag_url(nil, tag)}]))

      expect_tagging_result(
        [{:success => true, :href => api_conversion_host_url(nil, conversion_host), :tag_category => tag1[:category], :tag_name => tag1[:name]},
         {:success => true, :href => api_conversion_host_url(nil, conversion_host), :tag_category => tag2[:category], :tag_name => tag2[:name]}]
      )
      expect(conversion_host.tags.count).to eq(0)
    end
  end
end
