require 'spec_helper'

describe Apartment::Tenant do
  context "using mysql", database: :mysql do

    before do
      subject.stub(:config).and_return config   # Use mysql database config for this test
    end

    describe "#adapter" do
      before do
        subject.reload!
      end

      it "should load mysql adapter" do
        subject.adapter
        Apartment::Adapters::Mysql2Adapter.should be_a(Class)
      end
    end

    # TODO this doesn't belong here, but there aren't integration tests currently for mysql
    # where to put???
    describe "#exception recovery", :type => :request do
      before do
        subject.reload!
        subject.create db1
      end
      after{ subject.drop db1 }

      # it "should recover from incorrect database" do
      #   session = Capybara::Session.new(:rack_test, Capybara.app)
      #   session.visit("http://#{db1}.com")
      #   expect {
      #     session.visit("http://this-database-should-not-exist.com")
      #   }.to raise_error
      #   session.visit("http://#{db1}.com")
      # end
    end

    context "with prefix and schemas" do
      describe "#create" do
        before do
          Apartment.configure do |config|
            config.prepend_environment = true
            config.use_schemas = true
          end

          subject.reload!(config) # switch to Mysql2SchemaAdapter
        end

        after { subject.drop "db_with_prefix" rescue nil }

        it "should create a new database" do
          subject.create "db_with_prefix"
        end
      end
    end
  end

  context "using postgresql", database: :postgresql do
    before do
      Apartment.use_schemas = true
      subject.stub(:config).and_return config   # Use postgresql database config for this test
    end

    describe "#adapter" do
      before do
        subject.reload!
      end

      it "should load postgresql adapter" do
        subject.adapter
        Apartment::Adapters::PostgresqlAdapter.should be_a(Class)
      end

      it "should raise exception with invalid adapter specified" do
        subject.stub(:config).and_return config.merge(:adapter => 'unknown')

        expect {
          Apartment::Tenant.adapter
        }.to raise_error
      end

      context "threadsafety" do
        before { subject.create db1 }
        after { subject.drop db1 }

        it 'has a threadsafe adapter' do
          subject.switch(db1)
          thread = Thread.new { subject.current_tenant.should == Apartment.default_schema }
          thread.join
          subject.current_tenant.should == db1
        end
      end
    end

    context "with schemas" do

      before do
        Apartment.configure do |config|
          config.excluded_models = []
          config.use_schemas = true
          config.seed_after_create = true
        end
        subject.create db1
      end

      after{ subject.drop db1 }

      describe "#create" do
        it "should seed data" do
          subject.switch db1
          User.count.should be > 0
        end
      end

      describe "#switch" do

        let(:x){ rand(3) }

        context "creating models" do

          before{ subject.create db2 }
          after{ subject.drop db2 }

          it "should create a model instance in the current schema" do
            subject.switch db2
            db2_count = User.count + x.times{ User.create }

            subject.switch db1
            db_count = User.count + x.times{ User.create }

            subject.switch db2
            User.count.should == db2_count

            subject.switch db1
            User.count.should == db_count
          end
        end

        context "with excluded models" do

          before do
            Apartment.configure do |config|
              config.excluded_models = ["Company"]
            end
            subject.init
          end

          it "should create excluded models in public schema" do
            subject.reset # ensure we're on public schema
            count = Company.count + x.times{ Company.create }

            subject.switch db1
            x.times{ Company.create }
            Company.count.should == count + x
            subject.reset
            Company.count.should == count + x
          end
        end
      end
    end
  end
end
