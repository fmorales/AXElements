module AX

  class << self

    # @return [Regexp]
    attr_reader :accessibility_prefix

    # @param [AXUIElementRef] element
    # @param [String] attr an attribute constant
    def raw_attr_of_element element, attr
      ptr  = Pointer.new(:id)
      code = AXUIElementCopyAttributeValue( element, attr, ptr )
      log_ax_call(element, code)
      ptr[0]
    end

    ##
    # Call {#raw_attr_of_element} and perform extra processing
    # to make sure the returned data is wrapped properly.
    #
    # @param [AXUIElementRef] element
    # @param [String] attr an attribute constant
    def attr_of_element element, attr
      ret = raw_attr_of_element(element, attr)
      id  = ATTR_MASSAGERS[CFGetTypeID(ret)]
      id  ? self.send(id,ret) : ret
    end

    ##
    # Takes an AXUIElementRef and gives you some kind of accessibility object.
    #
    # @param [AXUIElementRef] element
    # @return [Element]
    def element_attribute element
      klass = class_name(element).sub(@accessibility_prefix) { $1 }
      new_const_get(klass).new(element)
    end

    # @return [Array,nil]
    def array_attribute value
      if value.empty? || (ATTR_MASSAGERS[CFGetTypeID(value.first)] == 1)
        value
      else
        value.map { |element| element_attribute(element) }
      end
    end

    # @return [Boxed,nil]
    def boxed_attribute value
      return nil unless value
      box = AXValueGetType( value )
      ptr = Pointer.new( AXBoxType[box].type )
      AXValueGetValue( value, box, ptr )
      ptr[0]
    end

    ##
    # Like {#const_get} except that if the class does not exist yet then
    # it will create the class for you. If not used carefully, you could end
    # up creating a bunch of useless, possibly harmful, classes at run time.
    #
    # @param [#to_sym] const the value you want as a constant
    # @return [Class] a reference to the class being looked up
    def new_const_get const
      return const_get(const) if const_defined?(const)
      create_ax_class(const)
    end

    ##
    # @todo consider using the rails inflector
    #
    # Chomps off a trailing 's' if there is one and then looks up the constant.
    #
    # @param [#to_s] const
    # @return [Class,nil] the class if it exists, else returns nil
    def plural_const_get const
      const = const.to_s.chomp('s')
      return const_get(const) if const_defined?(const)
      nil
    end

    ##
    # Creates new class at run time and puts it into the {AX} namespace.
    # This method is called for each type of UI element that has not yet been
    # explicitly defined to define them at runtime.
    #
    # @param [#to_sym] class_name
    # @return [Class]
    def create_ax_class class_name
      klass = Class.new(Element) {
        AX.log.debug "#{class_name} class created"
      }
      const_set( class_name, klass )
    end

    ##
    # Finds the current mouse position and then calls {#element_at_position}.
    #
    # @return [AX::Element]
    def element_under_mouse
      mouse_point = carbon_point_from_cocoa_point(NSEvent.mouseLocation)
      element_at_position mouse_point
    end

    ##
    # This will give you the UI element located at the position given (if
    # there is one). If more than one element is at the position then the
    # z-order of the elements will be used to determine which is "on top".
    #
    # The co-ordinates should be specified with the origin being in the
    # top-left corner of the main screen.
    #
    # @param [CGPoint] point
    # @return [AX::Element]
    def element_at_position point
      element = Pointer.new( '^{__AXUIElement}' )
      code = AXUIElementCopyElementAtPosition( SYSTEM.ref, point.x, point.y, element )
      log_ax_call(SYSTEM.ref, code)
      element_attribute element[0]
    end

    ##
    # @todo should this take a lower level object?
    #
    # Get a list of elements, starting with the element you gave and riding
    # all the way up the hierarchy to the top level (should be the Application).
    #
    # @param [AX::Element] element
    # @return [Array<AX::Element>] the hierarchy in ascending order
    def hierarchy *elements
      element = elements.last
      return hierarchy(elements << element.parent) if element.respond_to?(:parent)
      return elements
    end

    # @param [AXUIElementRef] element low level accessibility object
    # @return [Array<String>]
    def attrs_of_element element
      array_ptr = Pointer.new( '^{__CFArray}' )
      code = AXUIElementCopyAttributeNames( element, array_ptr )
      log_ax_call(element, code)
      array_ptr[0]
    end

    # @param [AXUIElementRef] element low level accessibility object
    # @return [Array<String>]
    def actions_of_element element
      array_ptr = Pointer.new( '^{__CFArray}' )
      code = AXUIElementCopyActionNames( element, array_ptr )
      log_ax_call(element, code)
      array_ptr[0]
    end

    ##
    # @todo print view hierarchy using {#pretty_print}
    #
    # Uses the call stack and error code to log a message that might be
    # helpful in debugging.
    #
    # @param [AXUIElementRef] element
    # @param [Fixnum] code AXError value
    # @return [Fixnum] returns the code that was passed
    def log_ax_call element, code
      return code if code.zero?
      message = AXError[code] || 'UNKNOWN ERROR CODE'
      log.warn "[#{message} (#{code})] while trying #{caller}"
      log.info "Available attrs/actions were: #{attrs_of_element(element)} #{actions_of_element(element)}"
      log.debug "Backtrace: #{caller.description}"
      code
    end


    private

    ##
    # Mapping low level type ID numbers to methods to massage useful
    # objects from data.
    #
    # @return [Array<Symbol>]
    ATTR_MASSAGERS = []
    ATTR_MASSAGERS[AXUIElementGetTypeID()] = :element_attribute
    ATTR_MASSAGERS[CFArrayGetTypeID()]     = :array_attribute
    ATTR_MASSAGERS[AXValueGetTypeID()]     = :boxed_attribute

    ##
    # This array is order-sensitive, which is why there is a
    # nil object at index 0.
    #
    # @return [Class,nil]
    AXBoxType = [ nil, CGPoint, CGSize, CGRect, CFRange ]

    ##
    # A mapping of the AXError constants to human readable strings.
    #
    # @return [Hash{Fixnum=>String}]
    AXError = {
      KAXErrorFailure                           => 'Generic Failure',
      KAXErrorIllegalArgument                   => 'Illegal Argument',
      KAXErrorInvalidUIElement                  => 'Invalid UI Element',
      KAXErrorInvalidUIElementObserver          => 'Invalid UI Element Observer',
      KAXErrorCannotComplete                    => 'Cannot Complete',
      KAXErrorAttributeUnsupported              => 'Attribute Unsupported',
      KAXErrorActionUnsupported                 => 'Action Unsupported',
      KAXErrorNotificationUnsupported           => 'Notification Unsupported',
      KAXErrorNotImplemented                    => 'Not Implemented',
      KAXErrorNotificationAlreadyRegistered     => 'Notification Already Registered',
      KAXErrorNotificationNotRegistered         => 'Notification Not Registered',
      KAXErrorAPIDisabled                       => 'API Disabled',
      KAXErrorNoValue                           => 'No Value',
      KAXErrorParameterizedAttributeUnsupported => 'Parameterized Attribute Unsupported',
      KAXErrorNotEnoughPrecision                => 'Not Enough Precision'
    }

    ##
    # Take a point that uses the bottom left of the screen as the origin
    # and returns a point that uses the top left of the screen as the
    # origin.
    #
    # @param [CGPoint] point screen position in Cocoa screen coordinates
    # @return [CGPoint]
    def carbon_point_from_cocoa_point point
      carbon_point = nil
      NSScreen.screens.each { |screen|
        if NSPointInRect(point, screen.frame)
          height       = screen.frame.size.height
          carbon_point = CGPoint.new( point.x, (height - point.y - 1) )
        end
      }
      carbon_point
    end

    ##
    # Figures out what the name of the class of an element should be.
    # We have to be careful, because some things claim to have a subrole
    # but return nil.
    #
    # This method prefers to choose a class type based on the subrole value for
    # an accessibility object, and it will use the role if there is no subrole.
    #
    # @param [AXUIElementRef]
    # @return [String]
    def class_name element
      attrs = attrs_of_element(element)
      [KAXSubroleAttribute,KAXRoleAttribute].map { |attr|
        if attrs.include?(attr)
          value = raw_attr_of_element(element, attr)
          return value if value
        end
      }
    end

  end

  ### Initialize various constants and instance variables

  @accessibility_prefix = /[A-Z]+([A-Z][a-z])/

  # @return [AX::SystemWide]
  SYSTEM = element_attribute AXUIElementCreateSystemWide()

  # @return [AX::Application] the Mac OS X dock application
  DOCK = Application.application_with_bundle_identifier( 'com.apple.dock' )

  # @return [AX::Application] the Mac OS X Finder application
  FINDER = Application.application_with_bundle_identifier( 'com.apple.finder' )

end
