SELECT p.pubname,
       array_agg(n.nspname || '.' || c.relname) AS tables
  FROM pg_publication p
  JOIN pg_publication_rel pr ON pr.prpubid = p.oid
  JOIN pg_class c              ON c.oid     = pr.prrelid
  JOIN pg_namespace n          ON n.oid     = c.relnamespace
 WHERE p.pubname = 'my_publication'
 GROUP BY p.pubname;
 
