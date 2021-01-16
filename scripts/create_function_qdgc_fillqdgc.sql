/* query requirements:
    * PostGIS 3.1 
    * Existing table with countries in table named tbl_countries
*/
drop table if exists tbl_qdgc;
create table  tbl_qdgc (qdgc varchar(20), country varchar(50),level_qdgc int, cellsize_degrees decimal, lon_center decimal, lat_center decimal, area_km2 decimal, geom geometry);

do $$
begin
   /* Establishing counter which defindes the depth of the grid cell creation. Here from 1 (1/2 degree) to 5 (1/32 degree) */
   for counter in 1..3 loop
	
	with grid as (
		/* creating the grid */
  		select (st_squaregrid((1/(2^counter)), st_transform(geom,4326))).* ,name as continent
  		from tbl_countries where name = 'Tanzania'
	) 
	
	insert into tbl_qdgc 
	select qdgc_getqdgc(ST_X(ST_Centroid(geom)),ST_Y(ST_Centroid(geom)),3),continent, counter,(1/(2^counter)), ST_X(ST_Centroid(geom)) as lon,ST_Y(ST_Centroid(geom)) as lat,(st_area(st_transform(geom, 102008))/1000000), geom from grid;

	
   end loop;
end; $$
