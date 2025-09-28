# frozen_string_literal: true

# Source-License: Reports Helper Functions
# Provides reports-specific helper methods for templates and controllers

# Reports-specific helper functions
module ReportsHelpers
  # Format data for Chart.js with proper escaping
  def chart_data_for_js(data)
    JSON.generate(data).gsub('</script>', '<\/script>')
  end

  # Calculate percentage change between two values
  def percentage_change(current, previous)
    return 0 if previous.nil? || previous.zero?

    ((current.to_f - previous.to_f) / previous.to_f) * 100
  end

  # Format large numbers with abbreviations
  def format_large_number(number)
    return '0' unless number&.positive?

    case number
    when 0..999
      number.to_s
    when 1000..999_999
      "#{(number / 1000.0).round(1)}K"
    when 1_000_000..999_999_999
      "#{(number / 1_000_000.0).round(1)}M"
    else
      "#{(number / 1_000_000_000.0).round(1)}B"
    end
  end

  # Generate trend arrow based on percentage change
  def trend_arrow(percentage)
    if percentage.positive?
      '<i class="fas fa-arrow-up text-success"></i>'
    elsif percentage.negative?
      '<i class="fas fa-arrow-down text-danger"></i>'
    else
      '<i class="fas fa-minus text-muted"></i>'
    end
  end
end
