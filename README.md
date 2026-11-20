[![Test](https://github.com/wvk/redirectr/actions/workflows/test.yml/badge.svg)](https://github.com/wvk/redirectr/actions/workflows/test.yml)

# Redirectr

Redirectr carries a target URL through a workflow in a URL param or form field, so the last step can redirect there: back to the page where the user started, or forward to a page the app chose in advance. Back links work the same way.

Redirectr adds controller methods to every controller and provides view helpers.

Redirectr 1.1 is the last release of the 1.x line and keeps backward compatibility. Development continues with Redirectr 2.0.

## Installation

```ruby
gem 'redirectr'
```

Include the view helpers:

```ruby
module ApplicationHelper
  include Redirectr::ApplicationHelper
end
```

Redirectr 1.1 runs on Rails 7.1 and newer.

## Examples

### Contact Form

A contact form, linked from every page, returns the user to the page they came from.

The footer link:

```erb
<%= link_to 'Contact us!', new_contact_path(referrer_param => current_url) %>
```

The form passes the referrer on:

```erb
<%= form_for ... do |f| %>
  <%= hidden_referrer_input_tag %>
  <!-- ... -->
<% end %>
```

The `create` action redirects back:

```ruby
def create
  # ...
  redirect_to back_or_default
end
```

### Forward Targets

A referrer can name the page to continue to:

```erb
<%= link_to 'Sign in', new_session_path(referrer_param => ReferrerToken(checkout_url)) %>
```

After signing in, `redirect_to back_or_default` continues to the checkout. `ReferrerToken()` turns a URL into a referrer that works with every referrer format.

### Custom default_url

`back_or_default` falls back to `default_url`, which returns `root_url`. Override it per controller:

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

### Nesting Referrers

A workflow can branch into a subworkflow and still return to its start:

```erb
<%= link_to 'go back directly', referrer_or_current_url %>
<%= link_to 'add new Foobar before going back', new_foobar_url(:foobar => {:name => 'My Foo'}, referrer_param => referrer_or_current_url) %>
```

Each nesting level encodes the URL again, so deep nesting produces long URLs.

### `current_url`

`current_url` returns the URL of the current request, as received. Keyword arguments override path and query params the way `url_for` does:

```ruby
current_url                                  # => "http://example.com/projects/7/tasks?filter=done"
current_url(page: 2, anchor: "item-42")      # => "http://example.com/projects/7/tasks?filter=done&page=2#item-42"
current_url(project_id: 8)                   # => "http://example.com/projects/8/tasks?filter=done"
current_url(filter: nil)                     # => "http://example.com/projects/7/tasks"
current_url(params: { anchor: "x" })         # => "http://example.com/projects/7/tasks?anchor=x&filter=done"
```

- A key naming a path segment fills it; other keys become query params.
- `nil` drops a param.
- `anchor:` sets the fragment; a record becomes its `dom_id`.
- `params:` sets query params with names that `url_for` reserves, such as `anchor` or `host`.

The result is a `Redirectr::ReferrerToken`: `#to_s` returns the URL, `#to_param` the value for the referrer param.

## Security

The referrer param is user input, and Redirectr turns it into redirects and links. Redirectr accepts as referrer:

- a path with exactly one leading `/`
- an `http` or `https` URL on the request's host and port, or on a whitelisted host
- a URL matching a whitelist entry of another scheme

Other referrers raise `Redirectr::UrlNotInWhitelist` and are logged at info level.

Rails' open-redirect protection (default since `load_defaults 7.0`) restricts `redirect_to` to the current host. Redirects to whitelisted hosts and other schemes pass `allow_other_host: true`:

```ruby
redirect_to back_or_default, allow_other_host: true
```

### Whitelist

```ruby
YourApp::Application.configure do
  config.x.redirectr.whitelist = %w(
    http://localhost:3000
    https://my.host.com
    com.example.app:/oauth2redirect
    mailto:
  )
end
```

Entries are URL prefixes: scheme, host, port and the leading path segments match. `http` and `https` entries accept both schemes. An entry consisting of a scheme (`mailto:`) accepts every URL of that scheme; for an app scheme such as `com.example.app:`, that includes every deep link into the app.

Entries for `javascript:`, `data:` and `vbscript:` require signed, encrypted or token referrers. Boot raises `Redirectr::ConfigurationError` otherwise.

### Signed and Encrypted Referrers

```ruby
YourApp::Application.configure do
  config.x.redirectr.sign_referrer = true      # the URL followed by "--" and an HMAC
  # or
  config.x.redirectr.encrypt_referrer = true   # the URL encrypted and signed
end
```

Redirectr then accepts only referrers it issued itself, and raises `Redirectr::InvalidReferrerToken` for others. Signing yields the same value for the same URL; encryption hides the URL.

The secret is `config.x.redirectr.secret`, the credential `redirectr.secret` or `secret_key_base`, in that order. Services that share referrers share this secret. To rotate it, list the old secrets:

```ruby
config.x.redirectr.previous_secrets = [old_secret]
```

Boot raises `Redirectr::ConfigurationError` when more than one of `sign_referrer`, `encrypt_referrer` and `use_referrer_token` is enabled.

### Graceful Handling of Rejected Referrers

```ruby
YourApp::Application.configure do
  config.x.redirectr.discard_referrer_on_invalid_origin = true
end
```

`referrer_url` then returns `nil` for rejected referrers, so `back_or_default` falls back to its default.

### Token Mode (deprecated)

Token mode moves to a separate gem with Redirectr 2.0, and boot logs a deprecation warning while it is enabled. It maps random tokens to URLs, which keeps referrer params short:

```ruby
require 'redirectr/referrer_token/active_record_storage'

YourApp::Application.configure do
  config.x.redirectr.use_referrer_token = true
  config.x.redirectr.reuse_tokens = true # set to false to generate a new token for each and every link
  config.x.redirectr.storage_implementation = Redirectr::ReferrerToken::ActiveRecordStorage
end
```

`ActiveRecordStorage` needs the table `redirectr_referrer_tokens`:

```bash
bundle exec rails redirectr:install:migrations
bundle exec rails db:migrate
```

## Contributions

Contributions like bugfixes and new ideas are more than welcome. Please just fork this project on github (https://github.com/wvk/redirectr) and send me a pull request with your changes.

Thanks so far to:

* Falk Hoppe for Rails 2.3.x interoperability
* Dimitar Haralanov for Rails 3.0.x interoperability
* Raffael Schmid for spotting a typo in the gemspec description ;)
* Till Schulte-Coerne for removing implicit dependencies and cleaning up unused code

Copyright (c) 2010 Willem van Kerkhof <wvk@consolving.de>, released under the MIT license
