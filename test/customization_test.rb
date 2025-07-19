# frozen_string_literal: true

require_relative 'test_helper'

class CustomizationTest < Minitest::Test
  def setup
    super
    # Ensure clean state for each test
    FileUtils.rm_f(TemplateCustomizer::CUSTOMIZATIONS_FILE)
  end

  def teardown
    super
    # Clean up after each test
    FileUtils.rm_f(TemplateCustomizer::CUSTOMIZATIONS_FILE)
  end

  def test_default_customizations
    defaults = TemplateCustomizer.get_all_customizations

    assert defaults['branding']
    assert defaults['colors']
    assert defaults['text']
    assert defaults['layout']
    assert defaults['features']

    assert_equal 'Source License', defaults['branding']['site_name']
    assert_equal '#2c3e50', defaults['colors']['primary']
  end

  def test_get_customization_value
    # Test getting default values
    assert_equal 'Source License', TemplateCustomizer.get('branding.site_name')
    assert_equal '#2c3e50', TemplateCustomizer.get('colors.primary')
    assert_equal 'fallback', TemplateCustomizer.get('nonexistent.key', 'fallback')
  end

  def test_set_customization_value
    TemplateCustomizer.set('branding.site_name', 'Custom Name')

    assert_equal 'Custom Name', TemplateCustomizer.get('branding.site_name')

    # Test nested key creation
    TemplateCustomizer.set('new_category.new_key', 'new_value')

    assert_equal 'new_value', TemplateCustomizer.get('new_category.new_key')
  end

  def test_update_multiple_customizations
    updates = {
      'branding.site_name' => 'My Site',
      'colors.primary' => '#ff0000',
      'features.dark_mode' => true,
    }

    TemplateCustomizer.update_multiple(updates)

    assert_equal 'My Site', TemplateCustomizer.get('branding.site_name')
    assert_equal '#ff0000', TemplateCustomizer.get('colors.primary')
    assert TemplateCustomizer.get('features.dark_mode')
  end

  def test_customization_persistence
    TemplateCustomizer.set('branding.site_name', 'Persistent Name')

    # Create new instance to test persistence
    assert_equal 'Persistent Name', TemplateCustomizer.get('branding.site_name')

    # Verify file was created
    assert_path_exists TemplateCustomizer::CUSTOMIZATIONS_FILE
  end

  def test_reset_to_defaults
    # Set some custom values
    TemplateCustomizer.set('branding.site_name', 'Custom')
    TemplateCustomizer.set('colors.primary', '#ff0000')

    # Reset to defaults
    TemplateCustomizer.reset_to_defaults

    # Should return to default values
    assert_equal 'Source License', TemplateCustomizer.get('branding.site_name')
    assert_equal '#2c3e50', TemplateCustomizer.get('colors.primary')

    # File should be removed
    refute_path_exists TemplateCustomizer::CUSTOMIZATIONS_FILE
  end

  def test_export_customizations
    TemplateCustomizer.set('branding.site_name', 'Export Test')

    yaml_content = TemplateCustomizer.export_customizations

    assert_includes yaml_content, 'Export Test'
    assert_includes yaml_content, 'branding:'

    # Should be valid YAML
    parsed = YAML.safe_load(yaml_content)

    assert_equal 'Export Test', parsed['branding']['site_name']
  end

  def test_import_customizations
    yaml_content = {
      'branding' => { 'site_name' => 'Imported Site' },
      'colors' => { 'primary' => '#00ff00' },
    }.to_yaml

    success = TemplateCustomizer.import_customizations(yaml_content)

    assert success
    assert_equal 'Imported Site', TemplateCustomizer.get('branding.site_name')
    assert_equal '#00ff00', TemplateCustomizer.get('colors.primary')
  end

  def test_import_invalid_yaml
    invalid_yaml = 'invalid: yaml: content:'

    success = TemplateCustomizer.import_customizations(invalid_yaml)

    refute success
  end

  def test_get_categories
    categories = TemplateCustomizer.get_categories

    assert categories['branding']
    assert categories['colors']
    assert categories['text']
    assert categories['layout']
    assert categories['features']

    # Each category should have title, description, and icon
    categories.each_value do |category|
      assert category['title']
      assert category['description']
      assert category['icon']
    end
  end

  def test_customization_helpers_integration
    TemplateCustomizer.set('branding.site_name', 'Helper Test')
    TemplateCustomizer.set('colors.primary', '#ff0000')
    TemplateCustomizer.set('features.dark_mode', true)

    # Test helper integration
    helper = Object.new
    helper.extend(CustomizationHelpers)

    assert_equal 'Helper Test', helper.custom('branding.site_name')
    assert_equal '#ff0000', helper.custom_color('primary')
    assert helper.feature_enabled?('dark_mode')
  end

  def test_css_variables_generation
    TemplateCustomizer.set('colors.primary', '#ff0000')
    TemplateCustomizer.set('colors.secondary', '#00ff00')
    TemplateCustomizer.set('layout.hero_padding', '5rem 0')

    helper = Object.new
    helper.extend(CustomizationHelpers)

    css_vars = helper.custom_css_variables

    assert_includes css_vars, '--custom-primary: #ff0000'
    assert_includes css_vars, '--custom-secondary: #00ff00'
    assert_includes css_vars, '--custom-hero-padding: 5rem 0'
    assert_includes css_vars, ':root'
  end

  def test_custom_style_generation
    TemplateCustomizer.set('colors.hero_gradient_start', '#ff0000')
    TemplateCustomizer.set('colors.hero_gradient_end', '#00ff00')
    TemplateCustomizer.set('layout.hero_padding', '6rem 0')
    TemplateCustomizer.set('layout.card_border_radius', '20px')

    helper = Object.new
    helper.extend(CustomizationHelpers)

    # Test hero style
    hero_style = helper.custom_style('hero')

    assert_includes hero_style, 'linear-gradient'
    assert_includes hero_style, '#ff0000'
    assert_includes hero_style, '#00ff00'
    assert_includes hero_style, '6rem 0'

    # Test card style
    card_style = helper.custom_style('card')

    assert_includes card_style, '20px'

    # Test section style
    TemplateCustomizer.set('layout.section_padding', '4rem 0')
    section_style = helper.custom_style('section')

    assert_includes section_style, '4rem 0'
  end

  def test_file_creation_and_directory_structure
    # Ensure directory is created if it doesn't exist
    FileUtils.rm_rf('config')

    refute Dir.exist?('config')

    TemplateCustomizer.set('test.key', 'test_value')

    assert Dir.exist?('config')
    assert_path_exists TemplateCustomizer::CUSTOMIZATIONS_FILE
  ensure
    # Clean up
    FileUtils.rm_rf('config')
  end

  def test_yaml_safety
    # Test that we're using safe YAML loading
    dangerous_yaml = '--- !ruby/object:Object {}'

    # Should not raise an error, but should return false
    success = TemplateCustomizer.import_customizations(dangerous_yaml)

    refute success
  end

  def test_deep_nested_keys
    TemplateCustomizer.set('level1.level2.level3.key', 'deep_value')

    assert_equal 'deep_value', TemplateCustomizer.get('level1.level2.level3.key')

    # Test partial path access
    level2_data = TemplateCustomizer.get('level1.level2')

    assert_kind_of Hash, level2_data
    assert_equal 'deep_value', level2_data['level3']['key']
  end

  def test_boolean_and_numeric_values
    TemplateCustomizer.set('features.enabled', true)
    TemplateCustomizer.set('features.disabled', false)
    TemplateCustomizer.set('layout.width', 1200)
    TemplateCustomizer.set('layout.opacity', 0.8)

    assert TemplateCustomizer.get('features.enabled')
    refute TemplateCustomizer.get('features.disabled')
    assert_equal 1200, TemplateCustomizer.get('layout.width')
    assert_in_delta(0.8, TemplateCustomizer.get('layout.opacity'))
  end

  def test_merge_with_defaults
    # Set only some values
    TemplateCustomizer.set('branding.site_name', 'Custom Site')

    all_customizations = TemplateCustomizer.get_all_customizations

    # Should have custom value
    assert_equal 'Custom Site', all_customizations['branding']['site_name']

    # Should still have default values for other keys
    assert_equal 'Professional Software Licensing Made Simple', all_customizations['branding']['site_tagline']
    assert all_customizations['colors']['primary']
  end

  def test_error_handling_for_corrupted_file
    # Create a corrupted YAML file
    FileUtils.mkdir_p(File.dirname(TemplateCustomizer::CUSTOMIZATIONS_FILE))
    File.write(TemplateCustomizer::CUSTOMIZATIONS_FILE, 'corrupted: yaml: [invalid')

    # Should handle gracefully and return defaults
    value = TemplateCustomizer.get('branding.site_name')

    assert_equal 'Source License', value
  end

  def test_customization_overwrites
    # Set initial value
    TemplateCustomizer.set('branding.site_name', 'First Value')

    assert_equal 'First Value', TemplateCustomizer.get('branding.site_name')

    # Overwrite with new value
    TemplateCustomizer.set('branding.site_name', 'Second Value')

    assert_equal 'Second Value', TemplateCustomizer.get('branding.site_name')
  end

  def test_empty_key_handling
    assert_nil TemplateCustomizer.get('')
    assert_nil TemplateCustomizer.get('.')
    assert_equal 'default', TemplateCustomizer.get('', 'default')
  end

  def test_special_characters_in_values
    special_value = "Value with special chars: !@#$%^&*()[]{}|\\:;\"'<>?,./"
    TemplateCustomizer.set('test.special', special_value)

    assert_equal special_value, TemplateCustomizer.get('test.special')

    # Test persistence through save/load cycle
    yaml_content = TemplateCustomizer.export_customizations
    TemplateCustomizer.reset_to_defaults
    TemplateCustomizer.import_customizations(yaml_content)

    assert_equal special_value, TemplateCustomizer.get('test.special')
  end
end
