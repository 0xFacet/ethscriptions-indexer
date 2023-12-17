# Welcome to the pre-release version of the official Open Source Ethscriptions Indexer!

This indexer has been extracted and streamlined from the indexer that runs Ethscriptions.com. This indexer is *not* yet production-ready and has _not_ been verified to be consistent with the production Ethscriptions.com indexer. However you can still play with it as we build together!

## Installation Instructions

This is a Ruby on Rails app.

Run this command inside the directory of your choice to clone the repository:

```!bash
git clone https://github.com/0xfacet/eths-indexer
```

If you don't already have Ruby Version Manager installed, install it:

```bash
\curl -sSL https://get.rvm.io | bash -s stable
```

You might need to run this if there is an issue with gpg:

```bash
gpg2 --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
```

Now install ruby 3.2.2:

```bash
rvm install 3.2.2
```

On a Mac you might run into an issue with openssl. If you do you might need to run something like this:

```bash
rvm install 3.2.2 --with-openssl-dir=$(brew --prefix openssl@1.1)
```

Install the gems (libraries) the app needs:

```bash
bundle install
```

Install postgres if you don't already have it:

```bash
brew install postgresql
```

Create the database:

```bash
rails db:create
```

Migrate the database schema:

```bash
rails db:migrate
```

You will also need memcache to use this. You can install it with homebrew as well. Consult ChatGPT!

Set up your env vars by renaming `.sample.env` to `.env`. You will need an Alchemy API key for this to work!

Run the tests to make sure everything is set up correctly:

```bash
rspec
```

Now run the process to index ethscriptions!

```bash
bundle exec clockwork config/main_importer_clock.rb
```

Run this one to do async tasks like assign ethscription numbers:

```bash
bundle exec clockwork config/secondary_clock.rb
```

You'll want to keep these two running in the background so you can process everything.

Now start the web server on a port of your choice, for example 4000:

```bash
rails s -p 4000
```

You can use this web server to access the API! (Note: at the time of writing the API doesn't exist! But it will soon)
