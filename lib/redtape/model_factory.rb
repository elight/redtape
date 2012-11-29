module Redtape
  class ModelFactory
    attr_reader :model_accessor, :records_to_save, :model

    def initialize(data_mapper, model_accessor = nil)
      @data_mapper = data_mapper
      @model_accessor = model_accessor
      @records_to_save = []
    end

    def populate_model
      params = @data_mapper.params[model_accessor]

      @model = find_or_create_root_model_from(params)

      populators = [
        Populator::Root.new(
          :model       => @model,
          :attrs       => params_for_current_scope_only(params),
          :data_mapper => @data_mapper
        )
      ]
      populators.concat(
        create_populators_for(model, params).flatten
      )

      populators.each do |p|
        p.call
      end

      @model
    end

    private

    def find_associated_model(attrs, args = {})
      case args[:with_macro]
      when :has_many
        args[:on_association].find(attrs[:id])
      when :has_one
        args[:on_model].send(args[:for_association_name])
      end
    end

    def find_or_create_root_model_from(params)
      model_class = model_accessor.to_s.camelize.constantize
      if params[:id]
        model_class.send(:find, params[:id])
      else
        model_class.new
      end
    end

    def create_populators_for(model, attributes)
      attributes.each_with_object([]) do |key_value, association_populators|
        next unless key_value[1].is_a?(Hash)

        key, value       = key_value
        macro            = macro_for_attribute_key(key)
        associated_attrs =
          case macro
          when :has_many
            value.values
          when :has_one
            [value]
          end

        associated_attrs.inject(association_populators) do |populators, record_attrs|
          assoc_name = find_association_name_in(key)
          current_scope_attrs = params_for_current_scope_only(record_attrs)

          associated_model = find_or_initialize_associated_model(
            current_scope_attrs,
            :for_association_name => assoc_name,
            :on_model             => model,
            :with_macro           => macro
          )

          populator_class = "Redtape::Populator::#{macro.to_s.camelize}".constantize
          populators << populator_class.new(
            :model                => associated_model,
            :association_name     => assoc_name,
            :attrs                => current_scope_attrs,
            :parent               => model,
            :data_mapper          => @data_mapper
          )

          populators.concat(
            create_populators_for(associated_model, record_attrs)
          )
        end
      end
    end

    def find_or_initialize_associated_model(attrs, args = {})
      association_name, macro, model = args.values_at(:for_association_name, :with_macro, :on_model)

      association = model.send(association_name)
      if attrs[:id]
        find_associated_model(
          attrs,
          :on_model => model,
          :with_macro => macro,
          :on_association => association,
        ).tap do |record|
          records_to_save << record
        end
      else
        case macro
        when :has_many
          model.send(association_name).build
        when :has_one
          model.send("build_#{association_name}")
        end
      end
    end

    def macro_for_attribute_key(key)
      association_name = find_association_name_in(key).to_sym
      association_reflection = model.class.reflect_on_association(association_name)
      association_reflection.macro
    end

    def params_for_current_scope_only(attrs)
      attrs.dup.reject { |_, v| v.is_a? Hash }
    end

    ATTRIBUTES_KEY_REGEXP = /^(.+)_attributes$/

    def has_many_association_attrs?(key)
      key =~ ATTRIBUTES_KEY_REGEXP
    end

    def find_association_name_in(key)
      ATTRIBUTES_KEY_REGEXP.match(key)[1]
    end
  end
end