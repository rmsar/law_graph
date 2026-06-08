// ============================================================
// LEGISLATION GRAPH — Neo4j Aura Import Script
// ============================================================
// USAGE (Neo4j Aura):
//   Upload CSVs to a public HTTP host (GitHub raw, S3, GCS).
//   Replace BASE_URL below with your actual URL prefix.
//   Run each block in order in Neo4j Browser or Aura console.
//
// USAGE (local Neo4j):
//   Copy CSVs to $NEO4J_HOME/import/
//   Replace the URL with 'file:///nodes/countries.csv' etc.
// ============================================================

// SET THIS BEFORE RUNNING
:param baseUrl => 'https://raw.githubusercontent.com/rmsar/law_graph/refs/heads/main/neo4j-legislation-sample'

// ============================================================
// STEP 1 — CONSTRAINTS & INDEXES
// ============================================================

CREATE CONSTRAINT country_id IF NOT EXISTS FOR (c:Country) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT category_id IF NOT EXISTS FOR (c:Category) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT authority_id IF NOT EXISTS FOR (a:Authority) REQUIRE a.id IS UNIQUE;
CREATE CONSTRAINT law_id IF NOT EXISTS FOR (l:Law) REQUIRE l.id IS UNIQUE;
CREATE CONSTRAINT article_id IF NOT EXISTS FOR (a:Article) REQUIRE a.id IS UNIQUE;
CREATE CONSTRAINT penalty_id IF NOT EXISTS FOR (p:Penalty) REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT obligation_id IF NOT EXISTS FOR (o:ComplianceObligation) REQUIRE o.id IS UNIQUE;

CREATE INDEX law_status IF NOT EXISTS FOR (l:Law) ON (l.status);
CREATE INDEX law_domain IF NOT EXISTS FOR (l:Law) ON (l.effective_date);
CREATE INDEX article_law IF NOT EXISTS FOR (a:Article) ON (a.law_id);
CREATE INDEX obligation_type IF NOT EXISTS FOR (o:ComplianceObligation) ON (o.obligation_type);
CREATE INDEX obligation_entity IF NOT EXISTS FOR (o:ComplianceObligation) ON (o.target_entity);

// ============================================================
// STEP 2 — NODES
// ============================================================

// -- Countries
LOAD CSV WITH HEADERS FROM $baseUrl + '/nodes/countries.csv' AS row
MERGE (c:Country {id: row.id})
SET c.name        = row.name,
    c.code        = row.code,
    c.region      = row.region,
    c.legal_system = row.legal_system;

// -- Categories
LOAD CSV WITH HEADERS FROM $baseUrl + '/nodes/categories.csv' AS row
MERGE (c:Category {id: row.id})
SET c.name        = row.name,
    c.description = row.description,
    c.domain      = row.domain;

// -- Authorities
LOAD CSV WITH HEADERS FROM $baseUrl + '/nodes/authorities.csv' AS row
MERGE (a:Authority {id: row.id})
SET a.name       = row.name,
    a.type       = row.type,
    a.country_id = row.country_id,
    a.website    = row.website;

// -- Laws
LOAD CSV WITH HEADERS FROM $baseUrl + '/nodes/laws.csv' AS row
MERGE (l:Law {id: row.id})
SET l.title            = row.title,
    l.short_name       = row.short_name,
    l.official_reference = row.official_reference,
    l.enacted_date     = date(row.enacted_date),
    l.effective_date   = date(row.effective_date),
    l.status           = row.status,
    l.country_id       = row.country_id,
    l.category_id      = row.category_id,
    l.description      = row.description;

// -- Articles
LOAD CSV WITH HEADERS FROM $baseUrl + '/nodes/articles.csv' AS row
MERGE (a:Article {id: row.id})
SET a.number          = row.number,
    a.title           = row.title,
    a.content_summary = row.content_summary,
    a.law_id          = row.law_id,
    a.is_key_article  = (row.is_key_article = 'true');

// -- Penalties
LOAD CSV WITH HEADERS FROM $baseUrl + '/nodes/penalties.csv' AS row
MERGE (p:Penalty {id: row.id})
SET p.description  = row.description,
    p.penalty_type = row.penalty_type,
    p.min_amount   = toFloat(row.min_amount),
    p.max_amount   = toFloat(row.max_amount),
    p.currency     = row.currency,
    p.unit         = row.unit,
    p.law_id       = row.law_id;

// -- Compliance Obligations
LOAD CSV WITH HEADERS FROM $baseUrl + '/nodes/compliance_obligations.csv' AS row
MERGE (o:ComplianceObligation {id: row.id})
SET o.description      = row.description,
    o.obligation_type  = row.obligation_type,
    o.target_entity    = row.target_entity,
    o.deadline_days    = toInteger(row.deadline_days),
    o.recurring        = (row.recurring = 'true'),
    o.law_id           = row.law_id,
    o.article_id       = row.article_id;

// ============================================================
// STEP 3 — STRUCTURAL RELATIONSHIPS
// ============================================================

// Country -[:HAS_LAW]-> Law
MATCH (c:Country), (l:Law)
WHERE c.id = l.country_id
MERGE (c)-[:HAS_LAW]->(l);

// Law -[:HAS_ARTICLE]-> Article
MATCH (l:Law), (a:Article)
WHERE l.id = a.law_id
MERGE (l)-[:HAS_ARTICLE]->(a);

// Law -[:BELONGS_TO_CATEGORY]-> Category
MATCH (l:Law), (c:Category)
WHERE l.category_id = c.id
MERGE (l)-[:BELONGS_TO_CATEGORY]->(c);

// Law -[:HAS_PENALTY]-> Penalty
MATCH (l:Law), (p:Penalty)
WHERE l.id = p.law_id
MERGE (l)-[:HAS_PENALTY]->(p);

// Article -[:CREATES_OBLIGATION]-> ComplianceObligation
MATCH (a:Article), (o:ComplianceObligation)
WHERE a.id = o.article_id
MERGE (a)-[:CREATES_OBLIGATION]->(o);

// Law -[:HAS_OBLIGATION]-> ComplianceObligation
MATCH (l:Law), (o:ComplianceObligation)
WHERE l.id = o.law_id
MERGE (l)-[:HAS_OBLIGATION]->(o);

// Authority -[:OPERATES_IN]-> Country
MATCH (a:Authority), (c:Country)
WHERE a.country_id = c.id
MERGE (a)-[:OPERATES_IN]->(c);

// ============================================================
// STEP 4 — ENFORCEMENT RELATIONSHIPS
// ============================================================

LOAD CSV WITH HEADERS FROM $baseUrl + '/relationships/law_authority.csv' AS row
MATCH (l:Law {id: row.law_id})
MATCH (a:Authority {id: row.authority_id})
MERGE (a)-[r:ENFORCES {role: row.role}]->(l);

// ============================================================
// STEP 5 — LEGISLATIVE RELATIONSHIPS
// ============================================================

// Law -[:IMPLEMENTS]-> Law
LOAD CSV WITH HEADERS FROM $baseUrl + '/relationships/law_implements.csv' AS row
MATCH (from:Law {id: row.from_law_id})
MATCH (to:Law {id: row.to_law_id})
MERGE (from)-[r:IMPLEMENTS]->(to)
SET r.transposition_date = row.transposition_date,
    r.notes              = row.notes;

// Law -[:AMENDS]-> Law
LOAD CSV WITH HEADERS FROM $baseUrl + '/relationships/law_amends.csv' AS row
MATCH (from:Law {id: row.from_law_id})
MATCH (to:Law {id: row.to_law_id})
MERGE (from)-[r:AMENDS]->(to)
SET r.amendment_date = row.amendment_date,
    r.description    = row.description;

// Law -[:CROSS_REFERENCES]-> Law
LOAD CSV WITH HEADERS FROM $baseUrl + '/relationships/law_cross_references.csv' AS row
MATCH (from:Law {id: row.from_law_id})
MATCH (to:Law {id: row.to_law_id})
MERGE (from)-[r:CROSS_REFERENCES {type: row.relationship_type}]->(to)
SET r.notes = row.notes;

// Article -[:REFERENCES]-> Article
LOAD CSV WITH HEADERS FROM $baseUrl + '/relationships/article_references.csv' AS row
MATCH (from:Article {id: row.from_article_id})
MATCH (to:Article {id: row.to_article_id})
MERGE (from)-[r:REFERENCES {type: row.reference_type}]->(to)
SET r.notes = row.notes;

// ============================================================
// STEP 6 — VERIFICATION QUERIES
// ============================================================

// Node counts
MATCH (c:Country) RETURN 'Countries' AS label, count(c) AS count
UNION ALL MATCH (c:Category) RETURN 'Categories', count(c)
UNION ALL MATCH (a:Authority) RETURN 'Authorities', count(a)
UNION ALL MATCH (l:Law) RETURN 'Laws', count(l)
UNION ALL MATCH (a:Article) RETURN 'Articles', count(a)
UNION ALL MATCH (p:Penalty) RETURN 'Penalties', count(p)
UNION ALL MATCH (o:ComplianceObligation) RETURN 'Obligations', count(o);

// Relationship counts
MATCH ()-[r]->() RETURN type(r) AS rel_type, count(r) AS count ORDER BY count DESC;

// ============================================================
// SAMPLE QUERIES
// ============================================================

// Q1: All laws for a country with their categories
// MATCH (c:Country {code: 'PT'})-[:HAS_LAW]->(l:Law)-[:BELONGS_TO_CATEGORY]->(cat:Category)
// RETURN c.name, l.short_name, cat.name ORDER BY cat.name;

// Q2: Cross-border obligations by type for a target entity
// MATCH (country:Country)-[:HAS_LAW]->(l:Law)-[:HAS_OBLIGATION]->(o:ComplianceObligation)
// WHERE o.target_entity = 'Employer'
// RETURN country.code, l.short_name, o.obligation_type, o.deadline_days ORDER BY o.deadline_days;

// Q3: Which laws reference each other across countries?
// MATCH (l1:Law)-[:CROSS_REFERENCES]->(l2:Law)
// MATCH (c1:Country)-[:HAS_LAW]->(l1)
// MATCH (c2:Country)-[:HAS_LAW]->(l2)
// WHERE c1 <> c2
// RETURN c1.code, l1.short_name, l2.short_name, c2.code;

// Q4: Article lineage — find all articles that reference or implement a given article
// MATCH path = (a:Article)-[:REFERENCES*1..3]->(target:Article {id: 'ART016'})
// RETURN path;

// Q5: Heaviest penalty by country for HSE domain
// MATCH (c:Country)-[:HAS_LAW]->(l:Law)-[:BELONGS_TO_CATEGORY]->(cat:Category {domain:'HSE'})
// MATCH (l)-[:HAS_PENALTY]->(p:Penalty)
// RETURN c.code, l.short_name, p.max_amount, p.currency ORDER BY p.max_amount DESC;

// Q6: Obligations with shortest deadline (most urgent)
// MATCH (c:Country)-[:HAS_LAW]->(l:Law)-[:HAS_OBLIGATION]->(o:ComplianceObligation)
// WHERE o.deadline_days > 0
// RETURN c.code, l.short_name, o.description, o.deadline_days ORDER BY o.deadline_days ASC LIMIT 10;

// Q7: Full compliance map for an operator in Portugal
// MATCH (c:Country {code:'PT'})-[:HAS_LAW]->(l:Law)
// MATCH (l)-[:HAS_OBLIGATION]->(o:ComplianceObligation)
// OPTIONAL MATCH (auth:Authority)-[:ENFORCES]->(l)
// RETURN l.short_name, collect(DISTINCT o.description) AS obligations, collect(DISTINCT auth.name) AS regulators;
