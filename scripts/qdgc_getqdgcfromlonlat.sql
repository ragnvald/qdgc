CREATE OR REPLACE FUNCTION public.qdgc_getqdgcfromlonlat(lon_value double precision, 
														   lat_value double precision, 
														   depthlevel integer)
RETURNS setof text
LANGUAGE plpgsql
as $$
declare
	returnstring text;
begin

	return query select * from qdgc_getlonlat(lon_value,lat_value);

end $$;

select * from qdgc_getqdgcfromlonlat(7.77,-5.43534,5);
