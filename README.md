[![Test](https://github.com/wvk/redirectr/actions/workflows/test.yml/badge.svg)](https://github.com/wvk/redirectr/actions/workflows/test.yml)

# Redirectr

In many web applications, the user triggers actions that result in simple or complex workflows that should, after that workflow is finished, result in the user being redirected to the page where they initially started it. Another example would be a "back"-link on any page.
A simple but completely Un-RESTful way would be to store the "current" page in a cookie each time the user calls an action and redirect to the url stored there if needed.

A much better (and potentially even cacheable) way is to encode the "backlink" URL in a URL parameter or form field and pass it along with every workflow step until the last (or only) action uses it to redirect the user back to where they initially came from.

Redirectr really does nothing more than provide a simple API for exactly that.

Redirectr provides a few Controller and Helper methods. The Controller methods will be included in your ApplicationController, the Helper methods can be included in your ApplicationHelper (see Installation).

Redirectr 1.1 is the last release of the 1.x line, which keeps backward compatibility. All further development focuses on Redirectr 2.0.

## Installation

When using bundler, just add the following to your Gemfile

    gem 'redirectr'

and then call

    bundle install

To use the view helpers (`hidden_referrer_input_tag`, `link_to_back`), add the following to your `app/helpers/application_helper.rb`:

```ruby
module ApplicationHelper
  include Redirectr::ApplicationHelper
end
```

Redirectr 1.1 runs on Rails 7.1 and newer.

## Migrating from 0.1.x to 1.0.0

Please read this section if you are already using an older version of Redirectr in your project. Otherwise, you may skip it.

Pre-1.0 versions of Redirectr automatically included some view helpers (`hidden_referrer_input_tag`, `link_to_back`). This is no longer the case, so please add the following to your `app/helpers/application_helper.rb`:

```ruby
module ApplicationHelper
  include Redirectr::ApplicationHelper
end
```

Please note that methods like `current_path`, `referrer_path` have been removed. Only `current_url`, `referrer_url` exist. Please do also note that the value returned by these methods is not a String containing a URI value anymore. Instead, a `Redirectr::ReferrerToken` is returned which maps a token to a URI. To get the URI value, call `#to_s`; `redirect_to`, `link_to` and URL helpers take the `Redirectr::ReferrerToken` as it is. When used as a URL parameter, Rails calls `#to_param` which returns the token.

Summary:

```ruby
# pre-1.0.0:
referrer_url.inspect # => 'https://example.com/...'

# post-1.0.0:
referrer_url.inspect # => '#<Redirectr::ReferrerToken:... @url="..." @token="...">'
referrer_url.to_s    # => 'https://example.com/...'

# both:
redirect_to referrer_url
redirect_to back_or_default
link_to 'take me back', back_or_default(my_url)
```

## Examples

### Contact Form

Suppose you have an application with a contact form that can be reached via a footer link on every page. After submitting the form, the user should be redirected to the page they were on before clicking on the "contact form" link.

For the footer link to the contact form:

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
  redirect_to back_or_default
end
```

### Forward Targets

A referrer can also name a page to go *forward* to, chosen by your application in advance. Suppose your checkout requires the user to sign in, and after signing in, the user should continue to the checkout:

```erb
<%= link_to 'Sign in', new_session_path(referrer_param => ReferrerToken(checkout_url)) %>
```

After signing in, `redirect_to back_or_default` takes the user to the checkout. `ReferrerToken()` turns any URL into a referrer param value that matches your configuration (plain, signed, encrypted or token).

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

### Custom referrer param name

By default, the referrer is passed in the param `referrer`. To use a different name, e.g. a shorter one:

```ruby
YourApp::Application.configure do
  config.x.redirectr.referrer_param_name = :r
end
```

When building links, use `referrer_param` instead of the literal name, as in the examples above, so a changed name takes effect everywhere.

### Nesting referrers

Referrer params can be nested, which is helpful if your workflow involves branching into subworkflows. Thus, it is always possible to pass the referrer_param to another url:

```erb
<%= link_to 'go back directly', referrer_or_current_url %>
<%= link_to 'add new Foobar before going back', new_foobar_url(:foobar =>  {:name => 'My Foo'}, referrer_param => referrer_or_current_url) %>
```

NOTE: If your URLs include lots of params, it is very advisable to use Referrer Tokens instead of plain URLs to avoid "URI too long" errors. See "Token instead of URL" below.

### `current_url(anchor: ...)`

You can now pass an `anchor:` keyword to `current_url` to override the URL fragment.  
This is useful when linking back to a specific position in a long list (e.g., after editing an item).

**Example:**

```ruby
current_url(anchor: "item-42")
# => "http://example.com/projects/7/tasks?filter=done#item-42"
```

### Overriding params with `current_url`

`current_url` also accepts path and query params that override those of the current request, following the conventions of `url_for`. This is useful e.g. for linking back to another page of a paginated list:

```ruby
# on http://example.com/projects/7/tasks?filter=done
current_url(page: 2, anchor: "item-42")  # => "http://example.com/projects/7/tasks?filter=done&page=2#item-42"
current_url(project_id: 8)               # => "http://example.com/projects/8/tasks?filter=done"
current_url(filter: nil)                 # => "http://example.com/projects/7/tasks"
current_url(params: { anchor: "x" })     # => "http://example.com/projects/7/tasks?anchor=x&filter=done"
```

A key naming a path segment fills that segment, all other keys become query params, and `nil` removes a param. `anchor:` sets the fragment as described above; a record becomes its `dom_id`. Query params with names that `url_for` reserves for itself, such as `anchor` or `host`, go into `params:`.

Together with `back_or_default`, this redirects to the referrer if one was given, and otherwise to the current page with the page param set to 2, scrolled to `#item-42`:

```ruby
redirect_to back_or_default(current_url(page: 2, anchor: "item-42"))
```

## Unvalidated Redirect Mitigation

Simply redirecting to a URI provided by HTTP params is considered a security vulnerability (see OWASP cheat sheet https://cheatsheetseries.owasp.org/cheatsheets/Unvalidated_Redirects_and_Forwards_Cheat_Sheet.html). Earlier versions of redirectr did not take any potential issues into account, allowing all kinds of phishing attacks.

Redirectr offers three kinds of mitigation, two of them being optional:

* checking the referrer param against a whitelist before performing a redirect (mandatory): by default, the request's host name and port number are allowed and all other hosts are disallowed.
* signing, or encrypting and signing, the referrer URL with a secret: makes the referrer param absolutely tamper-proof but requires all services to share that secret in a multi-service deployment.
* using random tokens instead of referrer URLs and a token-to-URL lookup service. This leaves you with the additional side effect of also having a URL shortener. (deprecated, see below)

Since the referrer param is user input that ends up in redirects and links, Redirectr accepts only the following as referrer:

* a path with exactly one leading `/`
* an `http` or `https` URL on the request's host and port, or on a whitelisted host
* a URL matching a whitelist entry of another scheme

All other referrers raise `Redirectr::UrlNotInWhitelist` and are logged at info level.

Rails' own open-redirect protection (enabled by `load_defaults 7.0` and newer) restricts `redirect_to` to the current host. To redirect to whitelisted hosts or other schemes, pass `allow_other_host: true`:

```ruby
redirect_to back_or_default, allow_other_host: true
```

### Using the whitelist

By default, Redirectr accepts as referrer:

* paths starting with exactly one `/`, such as `/foo?bar=1#baz`. Protocol-relative URLs (`//other.host/`) and relative references (`?page=2`, `#top`, `other.host/`) are rejected.
* `http` and `https` URLs whose host (case-insensitive) and port equal those of the current request. The scheme counts through the port only: without an explicit port, a URL has port 80 for `http` and 443 for `https`.

You may add your own:

```ruby
YourApp::Application.configure do
  config.x.redirectr.whitelist = %w( http://localhost:3000 https://my.host.com )
end
```

Whitelist entries can also allow schemes other than `http` and `https`, e.g. for OAuth callbacks into a mobile app or for mail links:

```ruby
YourApp::Application.configure do
  config.x.redirectr.whitelist = %w( https://my.host.com com.example.app:/oauth2redirect mailto:support@example.com )
end
```

Redirectr checks the entries at boot and raises `Redirectr::ConfigurationError` for an entry without a scheme (`my.host.com`), an entry naming only a scheme (`mailto:`, `https:`), an `http` or `https` entry without a host, and an invalid URI. A referrer matches an entry when its URL parts match the entry's; schemes and hosts compare case-insensitively. An entry takes one of two forms:

* a URL with a host or a path, such as `https://my.host.com` or `com.example.app:/oauth2redirect`: matches URLs with the same scheme, host and port whose path begins with the entry's path segments. Without an explicit port, the scheme's default port applies (80 for `http`, 443 for `https`, none for app schemes). Path segments compare as a whole, so `com.example.app:/oauth2redirect` matches `com.example.app:/oauth2redirect?code=1` and `com.example.app:/oauth2redirect/done`, and leaves out `com.example.app:/oauth2redirect-evil`. Empty segments and trailing slashes are ignored, and so are the entry's query and fragment.
* an opaque URL, with something other than `/` after the scheme, such as `mailto:support@example.com` or `tel:+4930123456`: matches URLs with the same scheme and the same part after it, up to the query. `mailto:support@example.com` thus matches `mailto:support@example.com?subject=Hi`, and leaves out `mailto:support@example.com.au` and `mailto:support@example.com,other@example.com`.

`http` and `https` entries add to the request's origin: an `http` or `https` referrer passes if it matches the request's host and port or any `http` or `https` entry. For compatibility with Redirectr 1.0, this comparison covers host and port only; the scheme counts through its default port. So `https://my.host.com` (port 443) leaves out `http://my.host.com` (port 80), while `http://localhost:3000` also accepts `https://localhost:3000`. Redirectr 2.0 compares the scheme as well.

Referrers of all other schemes pass if they match an entry of exactly their scheme.

Entries for `javascript:`, `data:` and `vbscript:` run code in the page and therefore require signed, encrypted or token referrers. Boot raises `Redirectr::ConfigurationError` otherwise.

### Signed and encrypted referrers

To accept only referrers issued by your application, enable signing or encryption:

```ruby
YourApp::Application.configure do
  config.x.redirectr.sign_referrer = true      # the URL followed by "--" and an HMAC
  # or
  config.x.redirectr.encrypt_referrer = true   # the URL encrypted and signed
end
```

Redirectr then accepts only referrers it issued itself and raises `Redirectr::InvalidReferrerToken` for all others. A signed referrer stays readable and yields the same value for the same URL; an encrypted one hides the URL. Redirectr verifies the referrer first and then checks the URL it contains as described in "Using the whitelist".

The secret is taken from `config.x.redirectr.secret`, the credential `redirectr.secret` or `secret_key_base`, in that order. In a multi-service deployment, all services passing referrers to each other share this secret, so a dedicated `redirectr.secret` is preferable there. To rotate the secret, list the old ones:

```ruby
config.x.redirectr.previous_secrets = [old_secret]
```

Only one of `sign_referrer`, `encrypt_referrer` and `use_referrer_token` can be enabled at a time; boot raises `Redirectr::ConfigurationError` otherwise.

### Token instead of URL (URL-shortener)

Token mode is deprecated: it moves to a separate gem with Redirectr 2.0, and boot logs a deprecation warning while it is enabled.

Instead of using a URL in the referrer token, redirectr can act as a URL shortener that maps random tokens to URLs. This requires a storage_implementation to be defined:

```ruby
require 'redirectr/referrer_token/active_record_storage'

YourApp::Application.configure do
  config.x.redirectr.use_referrer_token = true
  config.x.redirectr.reuse_tokens = true # set to false to generate a new token for each and every link
  config.x.redirectr.storage_implementation = Redirectr::ReferrerToken::ActiveRecordStorage
end
```

This example requires a table named 'redirectr_referrer_tokens' to be present with two columns: `url` and `token`. To install and apply the required schema migrations, run:

```bash
bundle exec rails redirectr:install:migrations
bundle exec rails db:migrate
```

Apps upgrading from Redirectr 1.0 run both commands again to add the unique index on `token`.

Redirectr::ReferrerToken has two representations: #to_s displays the URL and #to_param its tokenized form. Depending on your config, this can be either a random token, a signed URL, an encrypted URL or the plaintext URL.

### Graceful Handling of Invalid Referrer Origins

Redirectr normally raises `Redirectr::UrlNotInWhitelist` when the referrer’s origin (host/protocol/port) is not allowed, and `Redirectr::InvalidReferrerToken` when a signed, encrypted or token referrer is invalid. If you prefer to **treat such cases as if no referrer was provided**, enable:

```ruby
YourApp::Application.configure do
  config.x.redirectr.discard_referrer_on_invalid_origin = true
end
```

With this option, `referrer_url` returns `nil` for invalid origins and invalid referrers rather than raising an exception, so any code using it naturally falls back to its own default handling.

## Contributions

Contributions like bugfixes and new ideas are more than welcome. Please just fork this project on GitHub (https://github.com/wvk/redirectr) and send me a pull request with your changes.

Thanks so far to:

* Falk Hoppe for Rails 2.3.x interoperability
* Dimitar Haralanov for Rails 3.0.x interoperability
* Raffael Schmid for spotting a typo in the gemspec description ;)
* Till Schulte-Coerne for removing implicit dependencies and cleaning up unused code

Copyright (c) 2010 Willem van Kerkhof <wvk@consolving.de>, released under the MIT license
