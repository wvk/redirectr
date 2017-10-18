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

## Examples

### Contact Form

Suppose you have an application with a contact form that can be reached via a footer link on every page. After submitting the form, the user should be redirected to the page he was before clicking on the "contact form" link.

for the footer link to the contact form:

    <%= link_to 'Contact us!', new_contact_path(referrer_param => current_url) %>

In the 'new contact' view:

    <%= form_for ... do |f| %>
      <%= hidden_referrer_input_tag %>
      <!-- ... -->
    <% end %>

and finally, in the 'create' action of your ContactsController:

    def create
      # ...
      redirect_to back_or_default
    end

### Custom default_url

The above will redirect the user back to the page specified in the referrer param. However, if you want to provide a custom fallback url per controller in case no referrer param is provided, just define the `#default_url` in your controller:

    class MyController < ApplicationController
      def default_url
        if @record
          my_record_path(@record)
        else
          my_record_index_path
        end
      end
    end

### Nesting referrers

Referrer params can be nested, which is helpful if your workflow involves branching into subworkflows. Thus, it is always possible to pass the referrer_param to another url:

    <%= link_to 'go back directly', referrer_or_current_url %>
    <%= link_to 'add new Foobar before going back', new_foobar_url(:foobar =>  {:name => 'My Foo'}, referrer_param => referrer_or_current_url) %>

for more detailed examples, see the Rdoc documentation.

### Contributions

Contributions like bugfixes and new ideas are more than welcome. Please just fork this project on github (https://github.com/wvk/redirectr) and send me a pull request with your changes.

Thanks so far to:

* Falk Hoppe for Rails 2.3.x interoperability
* Dimitar Haralanov for Rails 3.0.x interoperability
* Raffael Schmid for spotting a typo in the gemspec description ;)

## Changelog

0.1.1: deprecate *_path methods; improve Rails 5 compatibility by removing `alias` in view helpers
0.1.0: Use absolute URI instead of path in current_path method
0.0.8: Use ActiveSupport::Concern (Thanks to Dimitar Haralanov)
0.0.7: Add Rails 3.0 compatibility (Thanks to Falk Hoppe)

Copyright (c) 2010-2017 Willem van Kerkhof <wvk@consolving.de>, released under the MIT license
