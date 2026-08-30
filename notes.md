### Database System Cataloge

*This is the place where we can find all the information about the database data i.e. the tables, columns, etc. it's Meta Data (Data about Data). We can find all of this in the INFORMATION_SCHEMA which has multiple built in views that can retreive the required meta data.*

* [ ] Explain how to find all the data about the database and how to access it beside how to navigate it.

#### What are we going to cover during the lecture?

* [ ] What is the internal server structure and how can we access each part of the server and what is the main role of each part on the server.
* [ ] Subquery types
* [ ] Common Table Expressions CTEs

What are the differences between both of them and why are we in need to both types NOT ONLY ONE can cover all of our needs regarding the complex queries.

### Subqueries

*What is the purpose of the subquery? the main purpose here is to break the complex queries into smaller parts - queries - where each part of them do a specific smaller task.*

#### Subquery Types

*Here in this topic we should divide the subquery according to multiple segmentation:*

* The first segment is the dependency
  * Correlated subquery
  * Non-Correlated subquery
* The second segment is the result
  * Scalar - single value subquery
  * Row - single row subquery
  * Table - multiple rows and columns subquery
* The third segment is the location of the subquery
  * Subquery located in the SELECT
  * Subquery located in the FROM
  * Subquery located before the JOIN
  * Subquery located in the WHERE using the comparison operators or the logical operators (IN, ANY, EXIST, ALL)

##### Using the subquery in FROM clause... 

*The idea here is that we are going to build a subquery that will by default build a temporary result that can be used as a temporary table we can select from.*
