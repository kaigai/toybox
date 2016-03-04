require("RPostgreSQL")

#
# PostgreSQL connection parameters
#
PgParam_hostname <- "localhost"
PgParam_dbname <- "chembl"

#
# Utility routines
#

"||" <- function(a,b)
{
  if (is.character(c(a,b))) {
    base::paste(a,b,sep="")
  } else {
    base::"||"(a,b)
  }
}

# just for my convenience
vatts_full <- c("c1","c2","c3","c4","c5","c6","c7","c8","c9","c10",
                "c11","c12","c13","c14","c15","c16","c17","c18","c19","c20",
                "c21","c22","c23","c24","c25","c26","c27","c28","c29","c30",
                "c31","c32","c33","c34","c35","c36","c37","c38","c39","c40",
                "c41","c42")
vatts_small <- c("c1","c2","c3","c4","c5","c6","c7","c8","c9","c10")


#
# pgsql_kmeans - returns pair of id and cluster for each item
#
# arguments:
# relname - name of the target table (string)
# att_pk  - name of the primary key column (string)
# att_val - vector of the property columns (string[])
# n_clusters - number of clusters (integer)
# threshold - maximum distance to continue k-means repeat (float, default: 0.0)
#
pgsql_kmeans_tryblock <- function(conn, relname, att_pk, att_val,
                                  n_clusters, threshold=0.0)
{
  #
  # Init: construction of pg_temp.cluster_map based on random
  #
  sql1 <- "SELECT " || att_pk || ", " ||
              "(random() * " || n_clusters || ")::int + 1 cid " ||
            "INTO pg_temp.cluster_map " ||
            "FROM " || relname
  print(sql1)

  #
  # Init: construction of pg_temp.centroid according to the cluster_map
  #
  sql2 <- "SELECT cid"
  for (att in att_val)
  {
    sql2 <- sql2 || ", avg(" || att || ") " || att
  }
  sql2 <- sql2 || " INTO pg_temp.centroid " ||
                  " FROM pg_temp.cluster_map c, " || relname || " r " ||
                  "WHERE c." || att_pk || " = r." || att_pk ||
                  " GROUP BY cid"
  print(sql2)

  #
  # Repeat: calculation of the distance between each item and centroid,
  #         then item shall belong to the closest cluster on the next
  #
  sql3 <- "SELECT " || att_pk || ", cid INTO pg_temp.cluster_map_new " ||
            "FROM (SELECT row_number() OVER w rank, " ||
                         "r." || att_pk || ", c.cid, " ||
                         "sqrt("
  is_first <- 1
  for (att in att_val) 
  {
    sql3 <- sql3 || ifelse(is_first, "", " + ") ||
            "(r." || att || " - c." || att || ")^2"
    is_first <- 0
  }
  sql3 <- sql3 || ") dist FROM " || relname || " r, centroid c) new_dist " ||
          "WINDOW w AS (PARTITION BY " || att_pk ||" ORDER BY dist)) foo " ||
          "WHERE rank = 1"
  print(sql3)

  #
  # Repeat: check differences between cluster_map and cluster_map_new
  #
  sql4 <- "SELECT count(*) FROM (" ||
          "SELECT * FROM pg_temp.cluster_map " ||
          "EXCEPT ALL " ||
          "SELECT * FROM pg_temp.cluster_map_new" ||
          ") diff"
  print(sql4)

  #
  # Repeat: if SQL4 has any result, cluster_map_new is renamed to
  #
  sql5a <- "DROP TABLE pg_temp.cluster_map"
  sql5b <- "ALTER TABLE pg_temp.cluster_map_new RENAME TO cluster_map"
  sql5c <- "VACUUM ANALYZE pg_temp.cluster_map"

  

}

pgsql_kmeans <- function(relname, att_pk, att_val, n_clusters, threshold=0.0)
{
  # Open the database connection
  conn <- dbConnect(PostgreSQL(),
                    host=PgParam_hostname,
                    dbname=PgParam_dbname)
  e <- try(pgsql_kmeans_tryblock(conn,relname, att_pk, att_val,
                                 n_clusters, threshold))
  # clean up database session on error
  dbDisconnect(conn)
}
