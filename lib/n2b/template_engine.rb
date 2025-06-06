module N2B
  class TemplateEngine
    def initialize(template, data)
      @template = template
      @data = data
    end

    def render
      result = @template.dup
      
      # Process loops first (they can contain variables)
      result = process_loops(result)
      
      # Process conditionals
      result = process_conditionals(result)
      
      # Process simple variables
      result = process_variables(result)
      
      result
    end

    private

    def process_loops(content)
      # Match {#each array_name} ... {/each}
      content.gsub(/\{#each\s+(\w+)\}(.*?)\{\/each\}/m) do |match|
        array_name = $1
        loop_content = $2
        array_data = @data[array_name] || @data[array_name.to_sym] || []
        
        if array_data.is_a?(Array)
          array_data.map do |item|
            item_content = loop_content.dup

            # Process conditionals within the loop context
            if item.is_a?(Hash)
              # Create temporary data context with item data
              temp_data = @data.merge(item)
              temp_engine = TemplateEngine.new(item_content, temp_data)
              item_content = temp_engine.send(:process_conditionals, item_content)

              # Replace item variables like {description}, {file_reference}
              item.each do |key, value|
                item_content.gsub!(/\{#{key}\}/, value.to_s)
              end
            else
              # If item is a string, replace {.} with the item itself
              item_content.gsub!(/\{\.?\}/, item.to_s)
            end

            item_content
          end.join("")
        else
          ""
        end
      end
    end

    def process_conditionals(content)
      # Match {#if condition} ... {#else} ... {/if} or {#if condition} ... {/if}
      content.gsub(/\{#if\s+(.+?)\}(.*?)(?:\{#else\}(.*?))?\{\/if\}/m) do |match|
        condition = $1.strip
        if_content = $2
        else_content = $3 || ""
        
        if evaluate_condition(condition)
          if_content
        else
          else_content
        end
      end
    end

    def process_variables(content)
      # Replace {variable_name} with actual values
      content.gsub(/\{(\w+)\}/) do |match|
        var_name = $1
        value = @data[var_name] || @data[var_name.to_sym]
        value.to_s
      end
    end

    def evaluate_condition(condition)
      # Handle conditions like: status == 'IMPLEMENTED'
      if condition.match(/(\w+)\s*(==|!=)\s*['"]([^'"]+)['"]/)
        var_name = $1
        operator = $2
        expected_value = $3
        actual_value = @data[var_name] || @data[var_name.to_sym]

        case operator
        when '=='
          actual_value.to_s == expected_value
        when '!='
          actual_value.to_s != expected_value
        end
      else
        # Simple boolean check
        var_value = @data[condition] || @data[condition.to_sym]
        !!var_value
      end
    end
  end
end
