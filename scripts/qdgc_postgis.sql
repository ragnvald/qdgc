drop table if exists tbl_qdgc;
create table  tbl_qdgc (qdgc varchar(20), country varchar(50),qdgc_level int, qdgc_cellsize decimal, longitude decimal, latitude decimal, areakm2 decimal, geom geometry);

do $$
begin
   for counter in 1..5 loop
	
	with grid as (
  		select (st_squaregrid((1/(2^counter)), st_transform(geom,4326))).* ,name as continent
  		from tbl_countries where name = 'Tanzania'
	) 

	insert into tbl_qdgc 
	select '',continent, counter,(1/(2^counter)), ST_X(ST_Centroid(geom)) as lon,ST_Y(ST_Centroid(geom)) as lat,(st_area(st_transform(geom, 102008))/1000000), geom from grid;

	
   end loop;
end; $$
