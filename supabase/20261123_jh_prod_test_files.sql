-- ============================================================================
-- [운영] [PROD] 시험 자료의 첨부 파일 정리 (2026-11-23) — 다니엘님 "첨부 파일도 정리해"
-- 앞서 실행한 20261123_jh_prod_test_data_delete.sql 의 백업 표(zz_backup_prod_test_20261123)를 기준으로 찾습니다.
-- 파일 보관함: Supabase Storage › files
--
-- ① 조회만 — 지울 파일 목록. 결과를 Claude 에게 보여 주세요.
-- ② 주인이 지워진 첨부 기록(attachments 줄) 백업 후 삭제 — ① 확인 뒤 실행
-- 실제 파일 삭제는 ① 결과를 보고 따로 안내합니다 (Supabase 는 SQL 로 파일을 지우지 못하게 막아 둡니다).
-- ============================================================================

-- ① 지울 파일 목록 (조회만)
with bk as (
    select tbl, row_data from public.zz_backup_prod_test_20261123
),
-- 지운 자료 (app_store 목록은 지운 항목만)
gone as (
    select tbl, row_data as r from bk where tbl <> 'app_store'
    union all
    select 'app_store:' || (b.row_data->>'key'), e
    from bk b, jsonb_array_elements(case when jsonb_typeof(b.row_data->'value') = 'array' then b.row_data->'value' else '[]'::jsonb end) e
    where b.tbl = 'app_store'
      and (e::text like '%[PROD]%' or e::text ~ '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)')
),
gone_ids as (
    select distinct r->>'id' as id from gone where coalesce(r->>'id', '') <> ''
),
cand as (
    select r->>'path' as path, '지운 첨부 기록' as 이유 from gone where tbl = 'attachments' and r ? 'path'
    union
    select a.path, '주인이 지워진 첨부 기록' from public.attachments a where a.owner_id in (select id from gone_ids)
    union
    select o.name, '지운 자료 안에 경로' from storage.objects o
    where o.bucket_id = 'files' and exists (select 1 from gone g where strpos(g.r::text, o.name) > 0)
)
select c.path as 경로, string_agg(distinct c.이유, ' · ') as 이유,
       bool_or(o.id is not null) as 보관함에_있음,
       pg_size_pretty(max(coalesce((o.metadata->>'size')::bigint, 0))) as 크기,
       -- 남아 있는 다른 첨부 기록이 같은 파일을 쓰고 있으면 지우지 않습니다
       bool_or(exists (select 1 from public.attachments a2 where a2.path = c.path and a2.owner_id not in (select id from gone_ids))) as 다른_곳에서_사용중
from cand c
left join storage.objects o on o.bucket_id = 'files' and o.name = c.path
group by c.path
order by 1;


-- ② 주인이 지워진 첨부 기록 — 백업 후 삭제 (① 확인 뒤 실행)
begin;
insert into public.zz_backup_prod_test_20261123(tbl, row_data)
select 'attachments', to_jsonb(a) from public.attachments a
where a.owner_id in (
        select distinct row_data->>'id' from public.zz_backup_prod_test_20261123 where tbl <> 'app_store' and coalesce(row_data->>'id', '') <> ''
        union
        select distinct e->>'id'
        from public.zz_backup_prod_test_20261123 b,
             jsonb_array_elements(case when jsonb_typeof(b.row_data->'value') = 'array' then b.row_data->'value' else '[]'::jsonb end) e
        where b.tbl = 'app_store' and coalesce(e->>'id', '') <> ''
          and (e::text like '%[PROD]%' or e::text ~ '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)'))
  and not exists (select 1 from public.zz_backup_prod_test_20261123 x where x.tbl = 'attachments' and x.row_data->>'id' = a.id::text);
delete from public.attachments a
where exists (select 1 from public.zz_backup_prod_test_20261123 x where x.tbl = 'attachments' and x.row_data->>'id' = a.id::text);
commit;
select count(*) as 백업된_첨부_기록 from public.zz_backup_prod_test_20261123 where tbl = 'attachments';


-- ③ 지우기 전 마지막 확인 (조회만) — ① 의 파일이 남아 있는 자료(모든 표 · app_store) 어디에도 쓰이지 않는지
--    남은_곳에서_쓰는_수 가 0 인 파일만 지웁니다. 1 이상이면 정상 자료가 쓰는 파일이라 남깁니다.
with bk as (select tbl, row_data from public.zz_backup_prod_test_20261123),
gone as (
    select tbl, row_data as r from bk where tbl <> 'app_store'
    union all
    select 'app_store', e from bk b, jsonb_array_elements(case when jsonb_typeof(b.row_data->'value') = 'array' then b.row_data->'value' else '[]'::jsonb end) e
    where b.tbl = 'app_store' and (e::text like '%[PROD]%' or e::text ~ '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)')
),
files as (
    select o.name from storage.objects o
    where o.bucket_id = 'files' and exists (select 1 from gone g where strpos(g.r::text, o.name) > 0)
)
select f.name as 경로,
       (select coalesce(sum((xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I t where strpos(t::text, %L) > 0',
                    tb.table_name, f.name), false, true, '')))[1]::text::int), 0)
          from information_schema.tables tb
         where tb.table_schema = 'public' and tb.table_type = 'BASE TABLE' and tb.table_name <> 'zz_backup_prod_test_20261123') as 남은_곳에서_쓰는_수
from files f
order by 2 desc, 1;
-- (app_store 도 위 표 목록에 들어 있어 함께 검사됩니다)


-- ④ 지울 파일 — 폴더별 정리 (조회만). Storage › files 에서 이 목록대로 지웁니다.
--    폴더_통째로_지워도_됨 = true 이면 그 폴더 안 파일이 모두 지울 대상이라 폴더째 지워도 됩니다.
with bk as (select tbl, row_data from public.zz_backup_prod_test_20261123),
gone as (
    select row_data as r from bk where tbl <> 'app_store'
    union all
    select e from bk b, jsonb_array_elements(case when jsonb_typeof(b.row_data->'value') = 'array' then b.row_data->'value' else '[]'::jsonb end) e
    where b.tbl = 'app_store' and (e::text like '%[PROD]%' or e::text ~ '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)')
),
del as (
    select o.name from storage.objects o
    where o.bucket_id = 'files' and exists (select 1 from gone g where strpos(g.r::text, o.name) > 0)
),
d as (select regexp_replace(name, '/[^/]+$', '') as 폴더, regexp_replace(name, '^.*/', '') as 파일명 from del)
select d.폴더,
       count(*) as 지울_파일_수,
       (select count(*) from storage.objects o where o.bucket_id = 'files' and regexp_replace(o.name, '/[^/]+$', '') = d.폴더) as 폴더_전체_파일_수,
       count(*) = (select count(*) from storage.objects o where o.bucket_id = 'files' and regexp_replace(o.name, '/[^/]+$', '') = d.폴더) as 폴더_통째로_지워도_됨,
       string_agg(d.파일명, E'\n' order by d.파일명) as 지울_파일
from d group by d.폴더 order by 1;


-- ⑤ 정리 도구용 목록 (조회만) — 결과 한 칸(지울_파일_목록)을 그대로 복사해 정리 도구에 붙여 넣습니다.
--    남은 자료 어디에도 쓰이지 않는 파일(③ 이 0)만 담습니다.
with bk as (select tbl, row_data from public.zz_backup_prod_test_20261123),
gone as (
    select row_data as r from bk where tbl <> 'app_store'
    union all
    select e from bk b, jsonb_array_elements(case when jsonb_typeof(b.row_data->'value') = 'array' then b.row_data->'value' else '[]'::jsonb end) e
    where b.tbl = 'app_store' and (e::text like '%[PROD]%' or e::text ~ '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)')
),
files as (
    select o.name from storage.objects o
    where o.bucket_id = 'files' and exists (select 1 from gone g where strpos(g.r::text, o.name) > 0)
),
checked as (
    select f.name,
           (select coalesce(sum((xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I t where strpos(t::text, %L) > 0',
                        tb.table_name, f.name), false, true, '')))[1]::text::int), 0)
              from information_schema.tables tb
             where tb.table_schema = 'public' and tb.table_type = 'BASE TABLE' and tb.table_name <> 'zz_backup_prod_test_20261123') as used
    from files f
)
select count(*) as 파일_수, json_agg(name order by name)::text as 지울_파일_목록 from checked where used = 0;
