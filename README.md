# lxd-common [![Build Status](https://travis-ci.org/NexusSW/lxd-common.svg?branch=master)](https://travis-ci.org/NexusSW/lxd-common) [![Dependency Status](https://gemnasium.com/badges/github.com/NexusSW/lxd-common.svg)](https://gemnasium.com/github.com/NexusSW/lxd-common)

[![Maintainability](https://api.codeclimate.com/v1/badges/28fae322a45ffa75b771/maintainability)](https://codeclimate.com/github/NexusSW/lxd-common/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/28fae322a45ffa75b771/test_coverage)](https://codeclimate.com/github/NexusSW/lxd-common/test_coverage)

## Installation

> **NOTE:** Versions < 0.10 are considered pre-release while Version 0.9.8 is considered the first stable pre-release.  Make sure when filing issues that you are on at least 0.9.8 and upgrade to 0.10+ as soon as it is possible and available (imminent).

Add this line to your application's Gemfile:

```ruby
gem 'lxd-common', '~> 0.9', '>= 0.9.8'
```

Next execute:

    > bundle install

Or install it yourself with:

    > gem install lxd-common

## Background

This gem intends to completely obfuscate the complexities of communicating with an LXD host.  LXD exposes two methods of interaction: a legacy LXC compatible CLI interface, and a new REST API.  Both behave a bit differently, but remain equally valid for today, and will remain available for the forseeable future.  This gem exposes an interface that will remain consistent, no matter the underlying communication mechanism.

Do you want to:

* Control a local LXD host via the CLI?
* Control a local/remote LXD host via their REST API?
* Control a LXD host and not care where it's located or want to deal with the API variances?
* Oh!  and do you want to control a LXD host that's buried under 2-3+ layers of nesting?  _(some scenarios still under dev at LXD & upstream)_

You're covered.  You provide the credentials and we'll provide the agnostic API.

Coming soon: native clustering support

* (as you would guess) automatic failover of a container when a host goes offline
* While LXD used to be utilized by larger tools such as juju, openstack & kubernetes to deploy smaller dev-station deployments, LXD will soon be able to 'utilize' and 'deploy' those larger tools without dedicating the host metal or cloud instances to those tools.
* (role reversal) It'll be your choice who drives:  LXD or those other utilities.

You'll no longer have to dedicate your metal, or your cloud instances to these large scale deployments.  They can do other things, too, by containerizing all the things.

## Usage

This gem is split up into 2 functional areas:  Driver and Transport.  Constructing a driver object does require some environment specific information.  But once you have the driver object constructed, all else is generic.

### Driver

Drivers allow you to communicate with the LXD host directly and to perform all command and control operations such as creating a container, as well as starting/stopping/deleting and for setting and querying container configuration.

There are 2 different drivers at your disposal:

* NexusSW::LXD::Driver::Rest
* NexusSW::LXD::Driver::CLI

And once they're constructed, they both respond to the same API calls in the same way, and so you no longer need to deal with API variances.  The next sections tell you how to construct these drivers, but the final 'Driver methods' section, and everything afterwards, is completely agnostic.

#### REST Interface Driver

#### Local CLI Driver

#### CLI Driver "magic"

#### Driver methods

## Contributing: Development and Testing

Bug reports and pull requests are welcome on GitHub at <https://github.com/NexusSW/lxd-common>.  DCO signoffs are required.

After checking out this repo, and installing development dependencies via `bundle install`, you can run some quick smoke tests that exercise most code paths via `rake mock`.  This just exercises the gem without talking to an actual LXD host.

The full integration test suite `rake spec` requires:

* a local LXD host (> 2.0) with the REST API enabled on port 8443
* your user account to be in the lxd group
* a client certificate and key located in ~/.config/lxc/ named client.crt and client.key
* and that certificate to be trusted by the LXD host via `lxc config trust add ~/.config/lxc/client.crt`
* a decent internet connection.  Most of the test time is spent in downloading images and spinning up containers.  So the quicker your filesystem and internet, the quicker the tests will run.  As a benchmark, Travis runs the integration tests in (presently) ~6-7 minutes, which includes installation and setup time.  If feasible, set your LXD up to use BTRFS to speed up the nesting tests.

Refer to [spec/provision_recipe.rb](https://github.com/NexusSW/lxd-common/blob/master/spec/provision_recipe.rb) (Chef) if you need hints on how to accomplish this setup.

### TDD Cycle _(suggested)_

**NOTE:** In contrast to normal expectations, these tests are not isolated and are stateful in between test cases.  Pay attention to tests that expect a container to exist, or for a file to exist within a container.  (Apologies: integration test times would be exponentially higher if I didn't make this concession)

1. run `rake mock` to verify your dependencies.  Expect it to pass.  Fix whatever is causing failures.
2. Write your failing test case(s)
3. run `rake mock`.  If there are compilation errors or exceptions generated by the spec/support/mock_transport.rb that cause pre-existing tests to fail, fix them so that past tests pass, and that your new tests compile (if feasible), but fail.
4. Create your new functionality
5. run `rake mock` again.  Code the mock_transport (and/or potentially the mock_hk) to return the results that you expect the LXD host to return.
6. Repeat the above until `rake mock` passes
7. run `rake spec` to see if your changes work for real.  Or if you can't set your workstation up for integration tests as described above, submit a PR and let Travis tell you.

`rake mock` and `rake spec` must both pass before Travis will pass.

#### Development Goals

When developing your new functionality, keep in mind that this gem intends to obfuscate the differences in the behavior between LXD's CLI and REST interfaces.  The test suite is designed to expose such differences, and it may become necessary for you to create completely seperate implementations in order to make them behave identically.

Whether to expose the behavior of the CLI, or that of the REST interface, or something in between, will be up for debate on a case by case basis.  But they do need to have the same behavior.  And that should be in line with the behavior of other pre-existing functions, should they fall within the same category or interact.