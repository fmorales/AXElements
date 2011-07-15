# -*- coding: utf-8 -*-
##
# @abstract
#
# The abstract base class for all accessibility objects.
class AX::Element
  ##
  # Raised when a lookup fails
  class LookupFailure < ArgumentError
    def initialize name
      super "#{name} was not found"
    end
  end

  ##
  # Raised when trying to set an attribute that cannot be written
  class AttributeReadOnly < NoMethodError
    def initialize name
      super "#{name} is a read only attribute"
    end
  end

  ##
  # Raised when an implicit search fails
  class SearchFailure < Exception
    def initialize searcher, searchee
      super "Could not find `#{searchee}` as a child of #{searcher.inspect}"
    end
  end

  ##
  # @todo take a second argument of the attributes array; the attributes
  #       are already retrieved once to decide on the class type; if that
  #       can be cached and used to initialize an element, we can save a
  #       more expensive call to fetch the attributes
  #
  # @param [AXUIElementRef] element
  def initialize element
    @ref        = element
    @attributes = AX.attrs_of_element(element)
  end

  # @group Attributes

  # @return [Array<String>] cache of available attributes
  attr_reader :attributes

  # @param [Symbol] attr
  def attribute attr
    real_attribute = attribute_for attr
    raise LookupFailure.new(attr) unless real_attribute
    AX.attr_of_element(@ref, real_attribute)
  end

  ##
  # Needed to override inherited {NSObject#description}. If you want a
  # description of the object use {#inspect} instead.
  def description
    attribute :description
  end

  ##
  # @todo Is it worth caching? Does it matter if it matters to cache the PID?
  #
  # Get the process identifier for the application that the element
  # belongs to.
  #
  # @return [Fixnum]
  def pid
    @pid ||= AX.pid_of_element(@ref)
  end

  # @param [Symbol] attr
  def attribute_writable? attr
    real_attribute = attribute_for attr
    raise LookupFailure.new(attr) unless real_attribute
    AX.attr_of_element_writable?(@ref, real_attribute)
  end

  ##
  # We cannot make any assumptions about the state of the program after
  # you have set a value; at least not in the general case.
  #
  # @param [String] attr an attribute constant
  # @return the value that you set is returned
  def set_attribute attr, value
    raise AttributeReadOnly.new(attr) unless attribute_writable? attr
    real_attribute = attribute_for attr
    value = value.to_axvalue if value.kind_of? Boxed
    AX.set_attr_of_element(@ref, real_attribute, value)
    value
  end

  # @group Parameterized Attributes

  # @return [Array<String>] available parameterized attributes
  def param_attributes
    AX.param_attrs_of_element(@ref) # should we cache?
  end

  ##
  # @todo Merge this into {#method_missing} and other places once I
  #       understand it more, it just adds overhead right now
  #
  # @param [Symbol] attr
  def get_param_attribute attr, param
    real_attribute = param_attribute_for attr
    raise LookupFailure.new(attr) unless real_attribute
    AX.param_attr_of_element(@ref, real_attribute, param)
  end

  # @group Actions

  # @return [Array<String>] cache of available actions
  def actions
    AX.actions_of_element(@ref) # purposely not caching this array
  end

  ##
  # Ideally this method would return a reference to `self`, but since
  # this method inherently causes state change, the reference to `self`
  # may no longer be valid. An example of this would be pressing the
  # close button on a window.
  #
  # @param [String] name an action constant
  # @return [Boolean] true if successful
  def perform_action name
    real_action = action_for name
    raise LookupFailure.new(name) unless real_action
    AX.action_of_element(@ref, real_action)
  end

  # @group Search

  ##
  # Perform a breadth first search through the view hierarchy rooted at
  # the current element.
  #
  # See the documentation page {file:docs/Searching.markdown Searching}
  # on the details of how to search.
  #
  # @example Find the dock item for the Finder app
  #
  #   AX::DOCK.search( :application_dock_item, title:'Finder' )
  #
  # @param [Symbol,String] element_type
  # @param [Hash{Symbol=>Object}] filters
  # @return [AX::Element,nil,Array<AX::Element>,Array<>]
  def search element_type, filters = nil
    type = element_type.to_s.camelize!
    meth = ((klass = type.singularize) == type) ? :find : :find_all
    Accessibility::Search.new(self).send(meth, klass.to_sym, (filters || {}))
  end

  ##
  # We use {#method_missing} to dynamically handle requests to lookup
  # attributes or search for elements in the view hierarchy. An attribute
  # lookup is tried first.
  #
  # Failing both lookups, this method calls `super`.
  #
  # @example Attribute lookup of an element
  #
  #   mail   = AX::Application.application_with_bundle_identifier 'com.apple.mail'
  #   window = mail.focused_window
  #
  # @example Attribute lookup of an element property
  #
  #   window.title
  #
  # @example Simple single element search
  #
  #   window.button # => You want the first Button that is found
  #
  # @example Simple multi-element search
  #
  #   window.buttons # => You want all the Button objects found
  #
  # @example Filters for a single element search
  #
  #   window.button(title:'Log In') # => First Button with a title of 'Log In'
  #
  # @example Contrived multi-element search with filtering
  #
  #   window.buttons(title:'New Project', enabled:true)
  #
  # @example Attribute and element search failure
  #
  #   window.application # => SearchFailure is raised
  def method_missing method, *args
    if attr = attribute_for(method)
      return AX.attr_of_element(@ref, attr)
    end

    if self.respond_to?(:children)
      if (ret = search(method, args.first)).blank?
        raise SearchFailure.new(self, method)
      else
        return ret
      end
    end

    super
  end

  # @group Notifications

  ##
  # Register to receive a notification from an object.
  #
  # You can optionally pass a block to this method that will be given
  # an element equivalent to `self` and the name of the notification;
  # the block should return a truthy value that decides if the
  # notification received is the expected one.
  #
  # @param [String,Symbol] notif
  # @param [Float] timeout
  # @yield
  # @yieldparam [AX::Element] element
  # @yieldparam [String] notif
  # @yieldreturn [Boolean]
  # @return [Proc]
  def on_notification notif, &block
    AX.register_for_notif(@ref, notif_for(notif), &block)
  end

  # @endgroup

  ##
  # Overriden to produce cleaner output.
  def inspect
    msg  = "\#<#{self.class}" << pp_identifier
    msg << pp_position if attributes.include? KAXPositionAttribute
    msg << pp_children if attributes.include? KAXChildrenAttribute
    msg << pp_checkbox(:enabled) if attributes.include? KAXEnabledAttribute
    msg << pp_checkbox(:focused) if attributes.include? KAXFocusedAttribute
    msg << '>'
  end

  ##
  # Overriden to respond properly with regards to the dynamic
  # attribute lookups, but will return false on potential
  # search names.
  def respond_to? name
    return true if attribute_for(name)
    super
  end

  ##
  # Get the position of the element, if it has one.
  #
  # @return [CGPoint]
  def to_point
    attribute(:position).center(attribute :size)
  end

  ##
  # Used during implicit search to determine if searches yielded
  # responses.
  def blank?
    false
  end

  ##
  # @todo Need to add '?' to predicate methods, but how?
  #
  # Like {#respond_to?}, this is overriden to include attribute methods.
  def methods include_super = true, include_objc_super = false
    names = attributes.map { |x| AX.strip_prefix(x).underscore.to_sym }
    names + super
  end

  ##
  # Overridden so that equality testing would work. A hack, but the only
  # sane way I can think of to test for equivalency.
  def == other
    @ref == other.instance_variable_get(:@ref)
  end
  alias_method :eql?, :==
  alias_method :equal?, :==

  # @todo Do we need to override #=== as well?


  protected

  ##
  # Create an identifier for {#inspect} that should make it very
  # easy to identify.
  #
  # Currently we look for the value, and if it is not present then
  # we check the title, and if that is not present we add nothing. In
  # the future, it would be nice to have a more intelligent heuristic,
  # but I think this will work at least 80% of the time.
  def pp_identifier
    if attributes.include? KAXValueAttribute
      " value=#{attribute(:value).inspect}"
    elsif attributes.include? KAXTitleAttribute
      " #{attribute(:title).inspect}"
    else # @todo should we have other fallbacks?
      ''
    end
  end

  ##
  # Add the position of the element to the {#inspect} output.
  def pp_position
    position = attribute(:position)
    " (#{position.x}, #{position.y})"
  end

  ##
  # Add the number of children to the {#inspect} output.
  def pp_children
    child_count = AX.attr_count_of_element(@ref, KAXChildrenAttribute)
    " #{child_count} #{child_count == 1 ? 'child' : 'children'}"
  end

  ##
  # Add an attribute to {#inspect} with a checkbox to display the value.
  #
  # @param [Symbol] value
  # @return [String]
  def pp_checkbox value
    " #{value}[#{attribute(value) ? '✔' : '✘'}]"
  end

  ##
  # Try to turn an arbitrary symbol into notification constant, and
  # then get the value of the constant.
  #
  # @param [Symbol]
  # @return [String]
  def notif_for name
    name  = name.to_s
    const = "KAX#{name.camelize!}Notification"
    Kernel.const_defined?(const) ? Kernel.const_get(const) : name
  end

  # @todo Use a thread local variable instead of the class variable for @@array
  #       but we still need lock writes to @@const_map
  def attribute_for sym; (@@array = attributes).find { |x| x == @@const_map[sym] } end
  def action_for sym; (@@array = actions).find { |x| x == @@const_map[sym] } end
  def param_attribute_for sym; (@@array = param_attributes).find { |x| x == @@const_map[sym] } end

  # @return [Hash{Symbol=>String}] Memoized mapping of symbols to constants
  #   used for attribute/action lookups
  @@const_map = Hash.new do |hash,key|
    @@array.map { |x| hash[AX.strip_prefix(x).underscore.to_sym] = x }
    if hash.has_key? key
      hash[key]
    else # try other cases of transformations
      real_key = key.chomp('?').to_sym
      hash.has_key?(real_key) ? hash[key] = hash[real_key] : nil
    end
  end

end


require 'ax_elements/elements/application'
require 'ax_elements/elements/systemwide'
require 'ax_elements/elements/table'