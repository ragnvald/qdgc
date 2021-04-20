QDGC
====

This project supports the production and distribution of QDGC files. It provides a setup which allows for swift production of spatial data within a PostGIS database. It also provides tools to pull data off from the online database and into a geopackage file for distribution.

You will find tools and relevant templates in the following folders:

- **scripts** to produce PostGreSQL/PostGIS functions to create grids
- **templates** Folder containing different templates.

Run the following scripts in a PostGIS database version 3.1 or above from th equery tool after initiating a default postgis database named qdgc:
- create_function_qdgc_getqdgc.sql
- create_function_qdgc_getlonlat.sql
- create_function_qdgc_getrecursivestring.sql
- create_function_qdgc_fillqdgc.sql

The script to create qdgc for a country relies on a table named tbl_countries. This table should have a name column which is being used for selecting the approprate country polygon. The next thing you do is to run this in the query tool:

- select qdgc_fillqdgc('Uganda',5,1)

5 is the maximum QDGC level you want to produce. 1 means the produced table tbl_qdgc will be emptied before you run it. If you want to do several consequtive queries the next queries will have to carry the argument 0.

- select qdgc_fillqdgc('Uganda',5,1)
- select qdgc_fillqdgc('Tanzania',5,0)
- select qdgc_fillqdgc('Kenya',5,0)

Why did I code these tools? Information on the distribution of animal populations is essential for conservation planning and management. Unfortunately, shared coordinate-level data may have the potential to compromise sensitive species and generalized data are often shared instead to facilitate knowledge discovery and communication regarding species distributions. Sharing of generalized data is, unfortunately, often ad hoc and lacks scalable conventions that permit consistent sharing at larger scales and varying resolutions. 

One common convention in African applications is the Quarter Degree Grid Cells (QDGC) system. However, the current standard does not support unique references across the Equator and Prime Meridian. We present a method for extending QDGC nomenclature to support unique references at a continental scale for Africa. 

The extended QDGC provides an instrument for sharing generalized biodiversity data where laws, regulations or other formal considerations prevent or prohibit distribution of coordinate-level information. We recommend how the extended QDGC may be used as a standard, scalable solution for exchange of biodiversity information through development of tools for the conversion and presentation of multi-scale data at a variety of resolutions. In doing so, the extended QDGC represents an important alternative to existing approaches for generalized mapping and can help planners and researchers address conservation issues more efficiently.
