-- FUNCTION: public.qdgc_get_qdgc(double precision, double precision, integer)

-- DROP FUNCTION public.qdgc_get_qdgc(double precision, double precision, integer);

CREATE OR REPLACE FUNCTION public.qqdgc_fillqdgc(
	area_input text,
	qdgc_level int)
    RETURNS SETOF text 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
declare
	returnstring text;
	temp_row text;
	lonlat text;
	qdgc text;
begin

	drop table if exists tbl_qdgc;
	create table  tbl_qdgc (qdgc varchar(20), area_reference varchar(50),level_qdgc int, cellsize_degrees decimal, lon_center decimal, lat_center decimal, area_km2 decimal, geom geometry);

   	/* Establishing counter which defindes the depth of the grid cell creation. Here from 1 (1/2 degree) to 5 (1/32 degree) */
   	for counter in 1..qdgc_level loop
	
	with grid as (
		/* creating the grid */
  		select (st_squaregrid((1/(2^counter)), st_transform(geom,4326))).* ,name as area_reference
  		from tbl_countries where name = area_input
	) 
	
	insert into tbl_qdgc 
	select qdgc_getqdgc(ST_X(ST_Centroid(geom)),ST_Y(ST_Centroid(geom)),3),area_reference, counter,(1/(2^counter)), ST_X(ST_Centroid(geom)) as lon,ST_Y(ST_Centroid(geom)) as lat,(st_area(st_transform(geom, 102008))/1000000), geom from grid;

	
   end loop;
	
end
$BODY$;

select qqdgc_fillqdgc('Tanzania',2)
