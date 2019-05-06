# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module PostGIS
      module OID
        class Spatial < Type::Value
          # sql_type is a string that comes from the database definition
          # examples:
          #   "geometry(Point,4326)"
          #   "geography(Point,4326)"
          #   "geometry(Polygon,4326) NOT NULL"
          #   "geometry(Geography,4326)"
          def initialize(oid, sql_type)
            @sql_type = sql_type
            @geo_type, @srid, @has_z, @has_m = self.class.parse_sql_type(sql_type)
          end

          # sql_type: geometry, geometry(Point), geometry(Point,4326), ...
          #
          # returns [geo_type, srid, has_z, has_m]
          #   geo_type: geography, geometry, point, line_string, polygon, ...
          #   srid:     1234
          #   has_z:    false
          #   has_m:    false
          def self.parse_sql_type(sql_type)
            geo_type, srid, has_z, has_m = nil, 0, false, false

            if sql_type =~ /(geography|geometry)\((.*)\)$/i
              # geometry(Point)
              # geometry(Point,4326)
              params = Regexp.last_match(2).split(",")
              if params.first =~ /([a-z]+[^zm])(z?)(m?)/i
                has_z = Regexp.last_match(2).length > 0
                has_m = Regexp.last_match(3).length > 0
                geo_type = Regexp.last_match(1)
              end
              if params.last =~ /(\d+)/
                srid = Regexp.last_match(1).to_i
              end
            else
              # geometry
              # otherType(a,b)
              geo_type = sql_type
            end
            [geo_type, srid, has_z, has_m]
          end

          def spatial_factory
            @spatial_factory ||=
              RGeo::Geos::CAPIFactory.new(
                wkt_parser:       :geos,
                wkb_parser:       :geos,
                geo_type:         @geo_type,
                has_m_coordinate: @has_m,
                has_z_coordinate: @has_z,
                srid:             @srid
              )
          end

          def geographic?
            @sql_type =~ /geography/
          end

          def spatial?
            true
          end

          def type
            geographic? ? :geography : :geometry
          end

          # support setting an RGeo object or a WKT string
          def serialize(value)
            return if value.nil?
            geo_value = cast_value(value)

            # TODO - only valid types should be allowed
            # e.g. linestring is not valid for point column
            # raise "maybe should raise" unless RGeo::Feature::Geometry.check_type(geo_value)

            RGeo::WKRep::WKBGenerator.new(hex_format: true, type_format: :ewkb, emit_ewkb_srid: true)
                                     .generate(geo_value)
          end

          private

          def cast_value(value)
            return if value.nil?
            String === value ? parse(value) : value
          end

          def binary_string?(string)
            string[0] == "\x00" || string[0] == "\x01" || string[0, 4] =~ /[0-9a-fA-F]{4}/
          end

          # convert WKT/WKB string into RGeo object
          def parse(string)
            if binary_string?(string)
              spatial_factory.parse_wkb(string)
            else
              spatial_factory.parse_wkt(string)
            end
          rescue RGeo::Error::ParseError
            nil
          end

        end
      end
    end
  end
end
