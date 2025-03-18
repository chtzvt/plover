# Plover

Plover is a tiny, embeddable Ruby build system designed to provide "Just Enough to Be Comfortable".

Plover is not a Make/Rake clone. It's intended to make it easier to write clean, organized build scripts in plain Ruby.

To help you with that, Plover provides a lightweight DSL for defining build phases, managing configuration flags, and tracking build artifacts, making it easier to manage configuration, state, and shared logic across your build and release processes.

## Features

#### Tiny & Embeddable 

Plover consists of ~300 lines of plain Ruby, with no dependencies outside of the standard library.

Because Plover is built to be embeddable, you can copy/paste `lib/plover.rb` into your project if you'd rather not use the gem. 

#### Phased Build Process

Define your build steps in distinct phases (setup, before_build, build, after_build, teardown) using a clean DSL that doesn't get in your way.

#### Flags

Easily configure your builds using flags passed via environment variables or directly as parameters.

Plover will automatically pick up environment variables prefixed with `PLOVER_FLAG_` and merge them with your build configuration.

#### Artifacts

Track outputs from each build phase and retrieve them for further processing or validation.

#### Extensible

Plover provides a Concern system similar to ActiveSupport::Concern to help you organize and reuse common build functionality.


## Installation

You can install Plover as a gem:

```
gem install plover
```

Or, add it to your project’s Gemfile:

```
gem "plover"
```

Because Plover is built to be embeddable, you can also just copy/paste `lib/plover.rb` into your project if you'd rather not use RubyGems (it's ~300 lines of plain Ruby, with no dependencies outside of the standard library).

## Usage

Plover uses Plover to publish itself, so a real-world example can be found [in this repository](https://github.com/chtzvt/plover/blob/master/.github/workflows/publish.rb).


### Basic Example 

```ruby
require "plover" # or require_relative "path/to/your/plover.rb"

class MyBuilder < Plover::Builder
  # Require a flag named :my_flag
  expect_flags(:my_flag)

  # Setup phase: print a message
  phase(:setup) do
    puts "Setting up the build..."
  end

  # Build phase: simulate a build operation
  phase(:build) do
    puts "Building the project..."
    do_a_thing if flag(:my_flag)
  end

  # Teardown phase: print a cleanup message
  phase(:teardown) do
    puts "Cleaning up..."
  end

  def do_a_thing
    puts "I did a thing! #{flag(:my_flag)}"
  end 
end

# Create an instance with the required flag and run the build phases.
MyBuilder.new(my_flag: "cool").run
```

### Shared Concerns

```ruby
require "plover"

# Define a concern under the Plover::Builder::Common namespace.
module Plover::Builder::Common::Greeting
  extend Plover::Concern

  # When this module is included, the `included` block is stored and later evaluated
  # in the context of the including Builder.
  included do
    # Define an instance method.
    def greet_builder
      puts "(Concern) Hey there #{flag(:name)}!"
    end

    # Add a phase step in the setup phase.
    phase(:setup) do
      puts "A Builder and a Concern enter:"
    end

    # Prepend a step to the build phase that calls the class method from the concern.
    prepend_phase(:build) do
      self.class.greet_class
    end

    # Prepend a step to the after_build phase.
    prepend_phase(:after_build) do
      greet_builder
      puts "(Concern) See you later."
    end

    # Add a step to the teardown phase.
    phase(:teardown) do
      puts "fin."
    end
  end

  # Define class methods that will be extended onto the including class.
  class_methods do
    def greet_class
      puts "(Concern) Hello! I'm a Concern. We can prepend or append steps to phases, define class or instance methods, and access state."
    end
  end
end

# Define a builder subclass that uses the Greeting concern.
class MyBuilder < Plover::Builder
  # Include the concern by specifying its name.
  common_include "Greeting"

  # Optionally, you could include multiple concerns:
  #   common_include "Greeting", "SomethingElse"
  # or include all common modules:
  #   common_include_all

  # Register a build phase step that calls a builder method.
  phase(:build) do
    builder_greeting
  end

  # Register an after_build phase step.
  phase(:after_build) do
    builder_goodbye
  end

  def builder_greeting
    # Set a flag that can be used by the concern.
    set_flag(:name, self.class.name)
    puts "(Builder) Hi! I'm a Builder named #{flag(:name)}."
  end

  def builder_goodbye
    puts "(Builder) Goodbye!"
  end
end

# Instantiate and run the builder.
MyBuilder.new.run
```


## Running Your Build

Plover is typically invoked by running your build script (e.g. ruby path/to/your/Ploverfile.rb). You can pass configuration flags via environment variables:

```
PLOVER_FLAG_GEM_VERSION="v0.1.0" \
PLOVER_FLAG_RUBYGEMS_RELEASE_TOKEN="YOUR_TOKEN" \
PLOVER_FLAG_GITHUB_RELEASE_TOKEN="YOUR_TOKEN" \
ruby path/to/your/Ploverfile.rb
```

Environment variables will automatically be configured as Builder flags with a common convention (`PLOVER_FLAG_MY_OPTION` becomes `flag(:my_option)`).

## Contributing

Contributions, issues, and feature requests are welcome!
Feel free to check issues page.

1.	Fork the repository.
2.	Create a new branch (`git switch -c feature/my-feature`).
3.	Make your changes.
4.	Submit a pull request.


## License

This project is licensed under the MIT License. See LICENSE for details.

