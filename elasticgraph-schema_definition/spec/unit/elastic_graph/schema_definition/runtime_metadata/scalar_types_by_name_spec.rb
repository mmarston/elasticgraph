# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #scalar_types_by_name" do
      include_context "RuntimeMetadata support"

      it "dumps the coercion adapter" do
        metadata = scalar_type_metadata_for "BigInt" do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end
        end

        expect(metadata).to eq scalar_type_with(coercion_adapter_ref: {
          "name" => "ExampleScalarCoercionAdapter",
          "require_path" => "support/example_extensions/scalar_coercion_adapter"
        })
      end

      it "dumps the indexing preparer" do
        metadata = scalar_type_metadata_for "BigInt" do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"
            t.prepare_for_indexing_with "ExampleIndexingPreparer", defined_at: "support/example_extensions/indexing_preparer"
          end
        end

        expect(metadata).to eq scalar_type_with(indexing_preparer_ref: {
          "name" => "ExampleIndexingPreparer",
          "require_path" => "support/example_extensions/indexing_preparer"
        })
      end

      it "verifies the validity of the extension when `coerce_with` is called" do
        define_schema do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"

            expect {
              t.coerce_with "NotAValidConstant", defined_at: "support/example_extensions/scalar_coercion_adapter"
            }.to raise_error NameError, a_string_including("NotAValidConstant")
          end
        end
      end

      it "verifies the validity of the extension when `indexing_preparer` is called" do
        define_schema do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"

            expect {
              t.prepare_for_indexing_with "NotAValidConstant", defined_at: "support/example_extensions/indexing_preparer"
            }.to raise_error NameError, a_string_including("NotAValidConstant")
          end
        end
      end

      it "dumps runtime metadata for the all scalar types (including ones described in the GraphQL spec) so that the indexing preparer is explicitly defined" do
        dumped_scalar_types = define_schema.runtime_metadata.scalar_types_by_name.keys

        expect(dumped_scalar_types).to include("ID", "Int", "Float", "String", "Boolean")
      end

      it "allows `on_built_in_types` to customize scalar runtime metadata" do
        metadata = scalar_type_metadata_for "Int" do |s|
          s.on_built_in_types do |t|
            if t.is_a?(SchemaElements::ScalarType)
              t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
            end
          end
        end

        expect(metadata.coercion_adapter_ref).to eq({
          "name" => "ExampleScalarCoercionAdapter",
          "require_path" => "support/example_extensions/scalar_coercion_adapter"
        })
      end

      it "allows a grouping missing value placeholder to be defined" do
        metadata = scalar_type_metadata_for "BigInt" do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"
            t.grouping_missing_value_placeholder "NaN"
          end
        end

        expect(metadata.grouping_missing_value_placeholder).to eq("NaN")
      end

      it "defaults grouping missing value placeholder to nil when not specified" do
        metadata = scalar_type_metadata_for "BigInt" do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"
          end
        end

        expect(metadata.grouping_missing_value_placeholder).to be_nil
      end

      describe "inferred grouping missing value placeholders" do
        it "infers 'NaN' for float types" do
          %w[double float half_float scaled_float].each do |float_type|
            metadata = scalar_type_metadata_for "TestFloat" do |s|
              s.scalar_type "TestFloat" do |t|
                t.mapping type: float_type
                t.json_schema type: "number"
              end
            end

            expect(metadata.grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
          end
        end

        it "infers secure random string for string types" do
          %w[keyword text].each do |string_type|
            metadata = scalar_type_metadata_for "TestString" do |s|
              s.scalar_type "TestString" do |t|
                t.mapping type: string_type
                t.json_schema type: "string"
              end
            end

            expect(metadata.grouping_missing_value_placeholder).to eq(MISSING_STRING_PLACEHOLDER)
          end
        end

        it "infers 'NaN' for safe integer types" do
          %w[integer short byte].each do |int_type|
            metadata = scalar_type_metadata_for "TestInt" do |s|
              s.scalar_type "TestInt" do |t|
                t.mapping type: int_type
                t.json_schema type: "integer"
              end
            end

            expect(metadata.grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
          end
        end

        it "infers 'NaN' for long types with JSON-safe min/max range" do
          metadata = scalar_type_metadata_for "SafeLong" do |s|
            s.scalar_type "SafeLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer", minimum: -(2**53) + 1, maximum: (2**53) - 1
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
        end

        it "does not infer placeholder for long types with max too large" do
          metadata = scalar_type_metadata_for "UnsafeLong" do |s|
            s.scalar_type "UnsafeLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer", minimum: -(2**53) + 1, maximum: (2**60) - 1
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for long types with min too small" do
          metadata = scalar_type_metadata_for "UnsafeLong" do |s|
            s.scalar_type "UnsafeLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer", minimum: -(2**60), maximum: (2**53) - 1
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for long types with only minimum specified" do
          metadata = scalar_type_metadata_for "PartialLong" do |s|
            s.scalar_type "PartialLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer", minimum: 0
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for long types with only maximum specified" do
          metadata = scalar_type_metadata_for "PartialLong" do |s|
            s.scalar_type "PartialLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer", maximum: 1000
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for long types without min/max specified" do
          metadata = scalar_type_metadata_for "UnboundedLong" do |s|
            s.scalar_type "UnboundedLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer"
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end

        it "infers 'NaN' for unsigned_long types with safe maximum" do
          metadata = scalar_type_metadata_for "SafeUnsignedLong" do |s|
            s.scalar_type "SafeUnsignedLong" do |t|
              t.mapping type: "unsigned_long"
              t.json_schema type: "integer", maximum: (2**53) - 1
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
        end

        it "does not infer placeholder for unsigned_long types with unsafe maximum" do
          metadata = scalar_type_metadata_for "UnsafeUnsignedLong" do |s|
            s.scalar_type "UnsafeUnsignedLong" do |t|
              t.mapping type: "unsigned_long"
              t.json_schema type: "integer", maximum: (2**60) - 1
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for unsigned_long types without maximum specified" do
          metadata = scalar_type_metadata_for "UnboundedUnsignedLong" do |s|
            s.scalar_type "UnboundedUnsignedLong" do |t|
              t.mapping type: "unsigned_long"
              t.json_schema type: "integer"
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end

        it "checks boundary conditions for JSON-safe long ranges" do
          # Test exactly at the JSON_SAFE_LONG boundaries
          json_safe_min = -(2**53) + 1
          json_safe_max = (2**53) - 1

          # Safe: exactly at boundaries
          metadata = scalar_type_metadata_for "BoundaryLong" do |s|
            s.scalar_type "BoundaryLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer", minimum: json_safe_min, maximum: json_safe_max
            end
          end
          expect(metadata.grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)

          # Unsafe: minimum one below safe range
          metadata = scalar_type_metadata_for "UnsafeMinLong" do |s|
            s.scalar_type "UnsafeMinLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer", minimum: json_safe_min - 1, maximum: json_safe_max
            end
          end
          expect(metadata.grouping_missing_value_placeholder).to be_nil

          # Unsafe: maximum one above safe range
          metadata = scalar_type_metadata_for "UnsafeMaxLong" do |s|
            s.scalar_type "UnsafeMaxLong" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer", minimum: json_safe_min, maximum: json_safe_max + 1
            end
          end
          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder when placeholder is specified" do
          metadata = scalar_type_metadata_for "CustomString" do |s|
            s.scalar_type "CustomString" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string"
              t.grouping_missing_value_placeholder "CUSTOM"
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to eq("CUSTOM")
        end

        it "does not infer placeholder when placeholder is set to nil" do
          metadata = scalar_type_metadata_for "CustomString" do |s|
            s.scalar_type "CustomString" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string"
              t.grouping_missing_value_placeholder nil
            end
          end

          expect(metadata.grouping_missing_value_placeholder).to be_nil
        end
      end

      def scalar_type_metadata_for(name, &block)
        define_schema(&block)
          .runtime_metadata
          .scalar_types_by_name
          .fetch(name)
      end
    end
  end
end
