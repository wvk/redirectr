[![Test](https://github.com/wvk/redirectr/actions/workflows/test.yml/badge.svg)](https://github.com/wvk/redirectr/actions/workflows/test.yml)

# Redirectr

In many web applications, the user triggers actions that result in simple or complex workflows that should, after that workflow is finished, result in the user being redirected to the page where he initially started it. Another example would be a "back"-Link on any page.
A simple but completely Un-RESTful way would be to store the "current" page in a cookie each time the user calls an action and redirect to the url stored there if needed.

A much better (and potentially even cacheable) way is to encode the "backlink" URL in an URL parameter or form field and pass it along with every workflow step until the last (or only) action uses it to redirect the user back to where he initially came from.

Redirectr really does nothing more than provide a simple API for exactly that.

Redirectr provides a few Controller and Helper methods that will be included in your ApplicationController and ApplicationHelper, respectively.

## Installation

when Using bundler, just at the following to your Gemfile

    gem 'redirectr'

and then call

    bundle install

## Migrating from 0.1.x to 1.0.0

Please read this section if you are already using an older version of Redirectr in yout project. Otherwise, you may skip it.

Pre-1.0 versions of Redirectr automatically included some view helpers (`hidden_referrer_input_tag`, `link_to_back`). This is no longer the case, so please add the following to your `app/helper/application_helper.rb`:

```ruby
module ApplicationHelper
  include Redirectr::ApplicationHelper
end
````

Please note that methods like `current_path`, `referrer_path` have been removed. Only `current_url`, `referrer_url` exist. Please do also note that the value returned by these methods is not a String containing an URI value anymore. Instead, a `Redirectr::ReferrerToken` is returned which maps a token to an URI. To get the URI value, call `#to_s` (e.g. when used in a `redirect_to` call). When used as an URL parameter, Rails calls `#to_param` which returns the token.

Summary:

```ruby
# pre-1.0.0:
referrer_url.inspect # => 'https://example.com/...'
redirect_to referrer_url
redirect_to back_or_default

# post-1.0.0:
referrer_url.inspect # => '#<Redirectr::ReferrerToken:... @url="..." @token="...">'
redirect_to referrer_url.to_s
redirect_to back_or_default.to_s
# OR, if you mount Redirectr::Engine in your routes
redirect_to referrer_url
redirect_to back_or_default

# pre-1.0.0:
link_to 'take me back', back_or_default(my_url)

# post-1.0.0:
link_to 'take me back', back_or_default(my_url).to_s
# OR, if you mount Redirectr::Engine in your routes
link_to 'take me back', back_or_default(my_url)
```

## Examples

### Contact Form

Suppose you have an application with a contact form that can be reached via a footer link on every page. After submitting the form, the user should be redirected to the page he was before clicking on the "contact form" link.

for the footer link to the contact form:

```erb
<%= link_to 'Contact us!', new_contact_path(referrer_param => current_url) %>
```

In the 'new contact' view:

```erb
<%= form_for ... do |f| %>
  <%= hidden_referrer_input_tag %>
  <!-- ... -->
<% end %>
```

and finally, in the 'create' action of your ContactsController:

```ruby
def create
  # ...
  redirect_to back_or_default.to_s
end
```

### Custom default_url

The above will redirect the user back to the page specified in the referrer param. However, if you want to provide a custom fallback url per controller in case no referrer param is provided, just define the `#default_url` in your controller:

```ruby
class MyController < ApplicationController
  def default_url
    if @record
      my_record_path(@record)
    else
      my_record_index_path
    end
  end
end
```

### Nesting referrers

Referrer params can be nested, which is helpful if your workflow involves branching into subworkflows. Thus, it is always possible to pass the referrer_param to another url:

```erb
<%= link_to 'go back directly', referrer_or_current_url %>
<%= link_to 'add new Foobar before going back', new_foobar_url(:foobar =>  {:name => 'My Foo'}, referrer_param => referrer_or_current_url) %>
```

NOTE: If your URLs include lots of params, it is very advisable to use Referrer Tokens instead of plain URLs to avoid "URI too long" errors. See next section.

## Unvalidated Redirect Mitigation

Simply redirecting to an URI provided by HTTP params is considered a security vulnerability (see OWASP cheat sheet https://cheatsheetseries.owasp.org/cheatsheets/Unvalidated_Redirects_and_Forwards_Cheat_Sheet.html). Earlier versions of redirectr did not take any potential issues into account, allowing all kinds of phishing attacs.

Redirectr offers three kinds of mitigation, two of them being optional:

* checking the referrer param against a whitelist before performing a redirect (mandatory): by default, the request's host name and port number are allowed and all other hosts are disallowed.
* encrypting and signing the referrer URL using the Rails secret key base: makes the referrer param absolutely tamper-proof but requires all services to use the same secret_key_base in a multi-service deployment.
* using random tokens instead of referrer URLs and an token-to-URL lookup service. This leaves you with the additional side effect of also having an URL shortener.

### Using the whitelist

By default, Redirectr checks the protocol, hostname and port of the referrer against the corresponding values of the current request. You may add your own:

```ruby
YourApp::Application.configure do
  config.x.redirectr.whitelist = %w( http://localhost:3000 https://my.host.com )
end
```

### Token instead of URL (URL-shortener)

Instead of using a URL in the referrer token, redirectr can act as an URL shortener that maps random tokens to URLs. This requires a storage_implementation to be defined:

```ruby
require 'redirectr/referrer_token/active_record_storage'

YourApp::Application.configure do
  config.x.redirectr.use_referrer_token = true
  config.x.redirectr.reuse_tokens = true # set to false to generate a new token for each and every link
  config.x.redirectr.storage_implementation = Redirectr::ReferrerToken::ActiveRecordStorage
end
```

This example requires a table named 'redirectr_referrer_tokens' to be present with two columns: `url` and `token`. To install and apply the required schema migration, run:

```bash
bundle exec rails redirectr:install:migrations
bundle exec rails db:migrate
```

Redirectr::ReferrerToken has two representations: #to_s displays the URL and #to_param its tokenized form. Depending on your config, this can be either a random token, an encrypted URL or the plaintext URL.

### Graceful Handling of Invalid Referrer Origins

Redirectr normally raises `Redirectr::InvalidReferrerToken` when the referrer’s origin (host/protocol/port) is not allowed. If you prefer to **treat such cases as if no referrer was provided**, enable:

```ruby
YourApp::Application.configure do
  config.x.redirectr.discard_referrer_on_invalid_origin = true
end
```

With this option, `referrer_url` returns `nil` for invalid origins rather than raising an exception, so any code using it naturally falls back to its own default handling.

## Contributions

Contributions like bugfixes and new ideas are more than welcome. Please just fork this project on github (https://github.com/wvk/redirectr) and send me a pull request with your changes.

Thanks so far to:

* Falk Hoppe for Rails 2.3.x interoperability
* Dimitar Haralanov for Rails 3.0.x interoperability
* Raffael Schmid for spotting a typo in the gemspec description ;)
* Till Schulte-Coerne for removing implicit dependencies and cleaning up unused code

Copyright (c) 2010 Willem van Kerkhof <wvk@consolving.de>, released under the MIT license
