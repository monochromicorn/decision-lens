namespace :typesafe do
  desc "List the TypeSafe model names this account can use (makes one authenticated GET /v1/models request)"
  task models: :environment do
    Providers::Typesafe.new(model: "unused").list_models.each do |model|
      puts "#{model[:name]}\t#{model[:release_date]}"
    end
  end
end
