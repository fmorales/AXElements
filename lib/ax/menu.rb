require 'ax/element'
require 'mouse'

##
# UI element representing a menu. Not much to it...
class AX::Menu < AX::Element

  ##
  # Search the menu for a `menu_item` that matches the given
  # filters. The filters should be specified just as they would
  # be when calling {#search}.
  def item filters = {}, &block
    result = self.search :menu_item, filters, &block
    return result unless result.blank?
    raise Accessibility::SearchFailure.new(self, :menu_item, filters, &block)
  end

end
