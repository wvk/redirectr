[![Test](https://github.com/wvk/redirectr/actions/workflows/test.yml/badge.svg)](https://github.com/wvk/redirectr/actions/workflows/test.yml)

# Redirectr

In many web applications, users trigger actions that result in simple or complex workflows that should, after that workflow is finished, result in them being redirected to the page where they initially started it. Another example would be a "back"-link on any page.
A simple but completely Un-RESTful way would be to store the "current" page in a cookie each time the user calls an action and redirect to the url stored there if needed.

A much better (and potentially even cacheable) way is to encode the "backlink" URL in a URL parameter or form field and pass it along with every workflow step until the last (or only) action uses it to redirect the user back to where they initially came from.

Redirectr really does nothing more than provide a simple API for exactly that.

Redirectr provides a few Controller and Helper methods that will be included in your ApplicationController and ApplicationHelper, respectively.

## Installation

When using bundler, just add the following to your Gemfile

    gem 'redirectr'

and then call

    bundle install

Redirectr 2 runs on Rails 8.1 and newer and Ruby 3.2 and newer.

## Upgrading from Redirectr 1.x

Please read this section if you are already using Redirectr 1.x in your project. Otherwise, you may skip it.

* Hosts are Rails' to decide: `back_or_default` asks `url_from` and raises `Redirectr::UrlNotInWhitelist` for hosts other than the request's. List the hosts you redirect to in `config.action_controller.allowed_redirect_hosts`. See "Unvalidated Redirect Mitigation" below.
* `config.x.redirectr.whitelist` holds schemes other than `http` and `https`. Move its `http` and `https` entries to `config.action_controller.allowed_redirect_hosts`; boot raises `Redirectr::ConfigurationError` as long as one of them is present.
* The referrer is checked where it becomes a target, in `back_or_default` and `link_to_back`. `referrer_url` returns it unchecked.
* `config.x.redirectr.referrer_format` replaces `sign_referrer` and `encrypt_referrer`.
* Signed and encrypted referrers require `config.hosts`. See "Signed and encrypted referrers" below.
* Token mode (`use_referrer_token`, `reuse_tokens`, `storage_implementation`) has been removed. You may drop the `redirectr_referrer_tokens` table.
* Boot raises `Redirectr::ConfigurationError` as long as any of these old settings is present.
* Controllers register the view helpers, so you may remove `include Redirectr::ApplicationHelper` from your `ApplicationHelper`.
* `back_or_default` in views returns link targets that follow Rails' open-redirect rule.

## Examples

### Contact Form

Suppose you have an application with a contact form that can be reached via a footer link on every page. After submitting the form, users should be redirected to the page they were on before clicking that link.

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
<%= link_to 'Sign in', new_session_path(with_referrer(checkout_url)) %>
```

After signing in, `redirect_to back_or_default` takes the user to the checkout.

### `with_referrer`

`with_referrer` returns the referrer param as a Hash for URL helpers. Without an argument, it passes on the referrer of the current request, or else the current URL; with a URL, it sets that URL as referrer:

```erb
<%= link_to 'Sign in', new_session_path(with_referrer) %>
<%= link_to 'Sign in', new_session_path(with_referrer(checkout_url)) %>
<%= link_to 'Sign in', new_session_path(with_referrer(checkout_url).merge(other: "params")) %>
```

The param carries the name `referrer_param` returns, and its value matches your configuration (see "Signed and encrypted referrers" below). Like `back_or_default`, `with_referrer` also takes a `Redirectr::ReferrerToken`, such as one from `current_url`, or anything `url_for` takes.

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
<%= link_to_back 'go back directly' %>
<%= link_to 'add new Foobar before going back', new_foobar_url(:foobar =>  {:name => 'My Foo'}, referrer_param => referrer_or_current_url) %>
```

`link_to_back` links to the referrer or, if Rails' open-redirect rule rejects it, to the default. `referrer_or_current_url` passes the referrer on as it is; the service that finally redirects checks it.

NOTE: Each nesting level encodes the URL again. If your URLs include lots of params, deep nesting can lead to "URI too long" errors.

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

Redirectr offers two kinds of mitigation, one of them being optional:

* checking the referrer before performing a redirect (mandatory): `back_or_default` redirects to the request's host, to the hosts in `config.action_controller.allowed_redirect_hosts`, the list of Rails' open-redirect protection, and to the other schemes in Redirectr's whitelist.
* signing, or encrypting and signing, the referrer URL with a secret: makes the referrer param absolutely tamper-proof but requires all services to share that secret in a multi-service deployment.

The referrer param is user input, and a service may pass it on to the next one without ever redirecting to it. Redirectr therefore checks the referrer where it becomes a target: in the service that performs the redirect, against that service's own configuration. `back_or_default` accepts the following as referrer:

* a path with exactly one leading `/`
* an `http` or `https` URL on the request's host or on a host in `config.action_controller.allowed_redirect_hosts`
* a URL matching a whitelist entry of another scheme

All other referrers raise `Redirectr::UrlNotInWhitelist` and are logged at info level. This holds regardless of `config.action_controller.action_on_open_redirect` and of `allow_other_host`. To redirect to other schemes, pass `allow_other_host: true`:

```ruby
redirect_to back_or_default, allow_other_host: true
```

`allow_other_host: true` thus lets through the referrers `back_or_default` accepts, and a default of your choice. Always redirect with `back_or_default`: `referrer_url` returns the referrer unchecked.

The view helpers come in two kinds:

* link targets (`back_or_default` in views, `link_to_back`) apply the same check and fall back to the default.
* `referrer_or_current_url` and `hidden_referrer_input_tag` pass the referrer on as it is; the service that finally redirects checks it.

### Allowed hosts

Which hosts a service redirects to is Rails' decision, taken from that service's own configuration:

```ruby
YourApp::Application.configure do
  config.action_controller.allowed_redirect_hosts = %w( my.host.com .apps.example.com )
end
```

`back_or_default` asks Rails' `url_from`, which accepts the request's host and the hosts in this list, comparing the host only, regardless of scheme and port. The list takes what `config.hosts` takes, such as `.apps.example.com` for a domain and its subdomains, or a regular expression. In a multi-service deployment, each service lists the hosts it redirects to; a service that only passes a referrer on needs no entry for it.

Paths starting with exactly one `/`, such as `/foo?bar=1#baz`, stay on the request's host. Protocol-relative URLs (`//other.host/`) and relative references (`?page=2`, `#top`, `other.host/`) are rejected.

### Using the whitelist

Redirectr's whitelist allows schemes other than `http` and `https`, e.g. for OAuth callbacks into a mobile app or for mail links:

```ruby
YourApp::Application.configure do
  config.x.redirectr.whitelist = %w( com.example.app:/oauth2redirect mailto:support@example.com )
end
```

Redirectr checks the entries at boot and raises `Redirectr::ConfigurationError` for an entry without a scheme (`my.host.com`), an entry naming only a scheme (`mailto:`), an `http` or `https` entry (hosts belong in `config.action_controller.allowed_redirect_hosts`), and an invalid URI. A referrer matches an entry when its URL parts match the entry's; schemes and hosts compare case-insensitively. An entry takes one of two forms:

* a URL with a host or a path, such as `com.example.app:/oauth2redirect`: matches URLs with the same scheme, host and port whose path begins with the entry's path segments. Path segments compare as a whole, so `com.example.app:/oauth2redirect` matches `com.example.app:/oauth2redirect?code=1` and `com.example.app:/oauth2redirect/done`, and leaves out `com.example.app:/oauth2redirect-evil`. Empty segments and trailing slashes are ignored, and so are the entry's query and fragment.
* an opaque URL, with something other than `/` after the scheme, such as `mailto:support@example.com` or `tel:+4930123456`: matches URLs with the same scheme and the same part after it, up to the query. `mailto:support@example.com` thus matches `mailto:support@example.com?subject=Hi`, and leaves out `mailto:support@example.com.au` and `mailto:support@example.com,other@example.com`.

Entries for `javascript:`, `data:` and `vbscript:` run code in the page and therefore require a signed referrer format. Boot raises `Redirectr::ConfigurationError` otherwise.

### Signed and encrypted referrers

To accept only referrers issued by your application, choose a signed referrer format:

```ruby
YourApp::Application.configure do
  config.x.redirectr.referrer_format = :signed     # the URL followed by "--" and an HMAC
  # or
  config.x.redirectr.referrer_format = :encrypted  # the URL encrypted and signed
end
```

The default format `:plain` uses the URL as it is. With `:signed` or `:encrypted`, Redirectr accepts only referrers it issued itself and raises `Redirectr::InvalidReferrerToken` for all others. A signed referrer stays readable and yields the same value for the same URL; an encrypted one hides the URL. Redirectr verifies the referrer when reading it and checks the URL it contains at the redirect, as described above.

A referrer from `current_url` names the host of the current request, which Rails takes from the `Host` header. Signed formats therefore require `config.hosts`, so that Rails turns away requests for other hosts before Redirectr issues a referrer for them:

```ruby
YourApp::Application.configure do
  config.hosts = %w( my.host.com )
end
```

Boot raises `Redirectr::ConfigurationError` when a signed format is used while `config.hosts` is empty. Development and test are exempt.

Redirectr::ReferrerToken has two representations: #to_s displays the URL and #to_param its tokenized form. Depending on your config, this can be either the plaintext URL, a signed URL or an encrypted URL.

The secret is taken from `config.x.redirectr.secret`, the credential `redirectr.secret` or `secret_key_base`, in that order. In a multi-service deployment, all services passing referrers to each other share this secret, so a dedicated `redirectr.secret` is preferable there. To rotate the secret, list the old ones:

```ruby
config.x.redirectr.previous_secrets = [old_secret]
```

Gems can add formats with `Redirectr::ReferrerFormat.register(name, signed:) { format }`. The format responds to `encode(url)` and `decode(param)`; `decode` raises `Redirectr::InvalidReferrerToken` for values it rejects. `signed: true` marks formats that accept only values the app issued.

### Graceful Handling of Invalid Referrer Origins

Redirectr normally raises `Redirectr::UrlNotInWhitelist` when the referrer’s origin (host/protocol) is not allowed, and `Redirectr::InvalidReferrerToken` when a signed or encrypted referrer is invalid. If you prefer to **treat such cases as if no referrer was provided**, enable:

```ruby
YourApp::Application.configure do
  config.x.redirectr.discard_referrer_on_invalid_origin = true
end
```

With this option, `back_or_default` returns its default for referrers that are not allowed, and `referrer_url` returns `nil` for invalid signed or encrypted referrers rather than raising an exception, so any code using it naturally falls back to its own default handling.

## Contributions

Contributions like bugfixes and new ideas are more than welcome. Please just fork this project on GitHub (https://github.com/wvk/redirectr) and send me a pull request with your changes.

Thanks so far to:

* Falk Hoppe for Rails 2.3.x interoperability
* Dimitar Haralanov for Rails 3.0.x interoperability
* Raffael Schmid for spotting a typo in the gemspec description ;)
* Till Schulte-Coerne for removing implicit dependencies and cleaning up unused code

Copyright (c) 2010 Willem van Kerkhof <wvk@consolving.de>, released under the MIT license
