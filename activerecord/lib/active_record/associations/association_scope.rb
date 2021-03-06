module ActiveRecord
  module Associations
    class AssociationScope #:nodoc:
      include JoinHelper

      attr_reader :association, :alias_tracker

      delegate :klass, :owner, :reflection, :interpolate, :to => :association
      delegate :chain, :conditions, :options, :source_options, :active_record, :to => :reflection

      def initialize(association)
        @association   = association
        @alias_tracker = AliasTracker.new
      end

      def scope
        scope = klass.unscoped
        scope = scope.extending(*Array.wrap(options[:extend]))

        # It's okay to just apply all these like this. The options will only be present if the
        # association supports that option; this is enforced by the association builder.
        scope = scope.apply_finder_options(options.slice(
          :readonly, :include, :order, :limit, :joins, :group, :having, :offset))

        if options[:through] && !options[:include]
          scope = scope.includes(source_options[:include])
        end

        if select = select_value
          scope = scope.select(select)
        end

        add_constraints(scope)
      end

      private

      def select_value
        select_value = options[:select]

        if reflection.collection?
          select_value ||= options[:uniq] && "DISTINCT #{reflection.quoted_table_name}.*"
        end

        if reflection.macro == :has_and_belongs_to_many
          select_value ||= reflection.klass.arel_table[Arel.star]
        end

        select_value
      end

      def add_constraints(scope)
        tables = construct_tables

        chain.each_with_index do |reflection, i|
          table, foreign_table = tables.shift, tables.first

          if reflection.source_macro == :has_and_belongs_to_many
            join_table = tables.shift

            scope = scope.joins(join(
              join_table,
              table[reflection.association_primary_key].
                eq(join_table[reflection.association_foreign_key])
            ))

            table, foreign_table = join_table, tables.first
          end

          if reflection.source_macro == :belongs_to
            key         = reflection.association_primary_key
            foreign_key = reflection.foreign_key
          else
            key         = reflection.foreign_key
            foreign_key = reflection.active_record_primary_key
          end

          conditions = self.conditions[i]

          if reflection == chain.last
            scope = scope.where(table[key].eq(owner[foreign_key]))

            if reflection.type
              scope = scope.where(table[reflection.type].eq(owner.class.base_class.name))
            end

            conditions.each do |condition|
              if options[:through] && condition.is_a?(Hash)
                condition = { table.name => condition }
              end

              scope = scope.where(interpolate(condition))
            end
          else
            constraint = table[key].eq(foreign_table[foreign_key])

            if reflection.type
              type = chain[i + 1].klass.base_class.name
              constraint = constraint.and(table[reflection.type].eq(type))
            end

            scope = scope.joins(join(foreign_table, constraint))

            unless conditions.empty?
              scope = scope.where(sanitize(conditions, table))
            end
          end
        end

        scope
      end

      def alias_suffix
        reflection.name
      end

      def table_name_for(reflection)
        if reflection == self.reflection
          # If this is a polymorphic belongs_to, we want to get the klass from the
          # association because it depends on the polymorphic_type attribute of
          # the owner
          klass.table_name
        else
          reflection.table_name
        end
      end

    end
  end
end
