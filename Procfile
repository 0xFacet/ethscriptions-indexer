web: bundle exec puma -C config/puma.rb
release: rake db:migrate
main_importer_clock: bundle exec clockwork config/main_importer_clock.rb
secondary_clock: bundle exec clockwork config/secondary_clock.rb
worker: bundle exec rake jobs:work
