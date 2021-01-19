QDGC
====

This project supports the production and distribution of QDGC files. It provides a setup which allows for swift production of spatial data within a PostGIS database. It also provides tools to pull data off from the online database and into a geopackage file for distribution.

You will find tools and relevant templates in the following folders:

- **scripts** to produce PostGreSQL/PostGIS functions to create grids
- **templates** Folder containing different templates.

Scripts:
- create_function_qdgc_getqdgc.sql
- create_function_qdgc_getlonlat.sql
- create_function_qdgc_getrecursivestring.sql
- create_function_qdgc_fillqdgc.sql

Why did I code these tools? Information on the distribution of animal populations is essential for conservation planning and management. Unfortunately, shared coordinate-level data may have the potential to compromise sensitive species and generalized data are often shared instead to facilitate knowledge discovery and communication regarding species distributions. Sharing of generalized data is, unfortunately, often ad hoc and lacks scalable conventions that permit consistent sharing at larger scales and varying resolutions. 

One common convention in African applications is the Quarter Degree Grid Cells (QDGC) system. However, the current standard does not support unique references across the Equator and Prime Meridian. We present a method for extending QDGC nomenclature to support unique references at a continental scale for Africa. 

The extended QDGC provides an instrument for sharing generalized biodiversity data where laws, regulations or other formal considerations prevent or prohibit distribution of coordinate-level information. We recommend how the extended QDGC may be used as a standard, scalable solution for exchange of biodiversity information through development of tools for the conversion and presentation of multi-scale data at a variety of resolutions. In doing so, the extended QDGC represents an important alternative to existing approaches for generalized mapping and can help planners and researchers address conservation issues more efficiently.
