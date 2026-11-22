-- ============================================================================
-- [운영] [PROD] 시험 자료 삭제 — 백업 → 삭제 → (필요 시) 되돌리기 (2026-11-23)
-- 다니엘님 "운영에 데이터 중 [PROD]로 등록된 것들 초반 테스트용 데이터를 모두 찾아서 삭제"
--
-- 지우는 대상 (찾기 SQL 20261123_jh_prod_test_data_find.sql 결과 기준)
--   · 글자 '[PROD]' 가 들어간 줄
--   · [PROD] 업체 5곳 c1018 ~ c1022 와 파트너 아이디 5개 ptn00001 ~ ptn00005 에 연결된 줄
--     (업체 · 업무 · 계약 · 첨부 · 알림 등 그룹웨어 표)
--   · app_store 목록 4개 안의 해당 항목만 — 목록 자체(정상 자료)는 남깁니다
--       gwPartnerAccounts.v1(아이디) · gwPartnerIntakes.v1(파트너 접수) · gwPartnerAudit.v1(접속 기록) · gwPartnerDeptPerm.v1(본부 권한)
-- 지우지 않는 것: 킹오더챗 · 세일즈 등 다른 프로그램의 표, 비밀값 · 구글 캘린더 연결 · 번호표(id_counters)
--
-- 실행 순서 (Supabase 운영 › SQL Editor, 관리자만)
--   1단계 실행 → 마지막 두 결과(표별 백업 줄 수 · 목록 밖 표 경고)를 Claude 에게 보여 주기
--   → 확인되면 2단계 실행 → 화면 확인
--   문제가 있으면 3단계(되돌리기)
-- 주의: 첨부 줄을 지워도 저장소(파일 보관함)의 실제 파일은 남습니다. 필요하면 따로 정리합니다.
--       직원 화면이 열려 있으면 바뀐 목록을 다시 받아 오지만, 실행 뒤 한 번 새로고침을 안내하는 것이 안전합니다.
-- ============================================================================


-- =========================== 1단계: 백업 + 건수 확인 (지우지 않음) ===========================
begin;
create table if not exists public.zz_backup_prod_test_20261123 (
    tbl       text not null,
    row_data  jsonb not null,
    backed_at timestamptz not null default now()
);
do $$
declare
    t   text;
    re  text := '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)';
    tbls text[] := array['customers','works','contracts','cases','quotes','attachments','partner_intakes','pay_doc_requests',
                         'schedules','schedule_reads','collab_requests','notifications','notices','settlements','install_checks',
                         'local_tasks','todos','projects','supplies','price_book','pg_fees','vehicle_logs','vehicle_reservations'];
begin
    if exists (select 1 from public.zz_backup_prod_test_20261123) then
        raise exception '이미 백업이 있습니다. 1단계는 한 번만 실행합니다 (백업 표: zz_backup_prod_test_20261123).';
    end if;
    foreach t in array tbls loop
        if to_regclass('public.' || t) is not null then
            execute format('insert into public.zz_backup_prod_test_20261123(tbl, row_data)
                            select %L, to_jsonb(x) from public.%I x where x::text like %L or x::text ~ %L',
                           t, t, '%[PROD]%', re);
        end if;
    end loop;
    -- app_store 목록 4개는 통째로 백업 (되돌릴 때 그대로 돌려놓음)
    insert into public.zz_backup_prod_test_20261123(tbl, row_data)
    select 'app_store', to_jsonb(s) from public.app_store s
    where s.key in ('gwPartnerAccounts.v1', 'gwPartnerIntakes.v1', 'gwPartnerAudit.v1', 'gwPartnerDeptPerm.v1');
end $$;
commit;

-- 1-가. 표별 백업(= 2단계에서 지울) 줄 수
select tbl as 표, count(*) as 줄_수 from public.zz_backup_prod_test_20261123 group by tbl order by 2 desc;

-- 1-나. 위 목록 밖 표에서 나온 줄 (0줄이어야 정상 — 줄이 있으면 2단계 전에 Claude 에게 알려 주세요)
select table_name as 목록_밖_표,
       (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I t where t::text like %L or t::text ~ %L',
              table_name, '%[PROD]%', '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)'), false, true, '')))[1]::text::int as 줄_수
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE'
  and table_name not in ('app_store', 'zz_backup_prod_test_20261123', 'customers','works','contracts','cases','quotes','attachments','partner_intakes',
                         'pay_doc_requests','schedules','schedule_reads','collab_requests','notifications','notices','settlements','install_checks',
                         'local_tasks','todos','projects','supplies','price_book','pg_fees','vehicle_logs','vehicle_reservations')
  and (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I t where t::text like %L or t::text ~ %L',
              table_name, '%[PROD]%', '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)'), false, true, '')))[1]::text::int > 0;


-- =========================== 2단계: 삭제 (1단계 결과 확인 뒤) ===========================
begin;
do $$
declare
    t   text;
    n   integer;
    re  text := '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)';
    tbls text[] := array['customers','works','contracts','cases','quotes','attachments','partner_intakes','pay_doc_requests',
                         'schedules','schedule_reads','collab_requests','notifications','notices','settlements','install_checks',
                         'local_tasks','todos','projects','supplies','price_book','pg_fees','vehicle_logs','vehicle_reservations'];
begin
    if not exists (select 1 from public.zz_backup_prod_test_20261123) then
        raise exception '백업이 없습니다. 1단계를 먼저 실행해 주세요.';
    end if;
    foreach t in array tbls loop
        if to_regclass('public.' || t) is not null then
            execute format('delete from public.%I x where x::text like %L or x::text ~ %L', t, '%[PROD]%', re);
            get diagnostics n = row_count;
            if n > 0 then raise notice '% : % 줄 삭제', t, n; end if;
        end if;
    end loop;
    -- app_store 목록 3개 — 해당 항목만 빼고 순서는 그대로
    update public.app_store s
       set value = (select coalesce(jsonb_agg(e.v order by e.i), '[]'::jsonb)
                    from jsonb_array_elements(s.value) with ordinality as e(v, i)
                    where not (e.v::text like '%[PROD]%' or e.v::text ~ re)),
           updated_at = now()
     where s.key in ('gwPartnerAccounts.v1', 'gwPartnerIntakes.v1', 'gwPartnerAudit.v1')
       and jsonb_typeof(s.value) = 'array';
    -- 본부 권한 — 아이디(소문자)를 이름으로 한 묶음
    update public.app_store
       set value = value - array['ptn00001','ptn00002','ptn00003','ptn00004','ptn00005'], updated_at = now()
     where key = 'gwPartnerDeptPerm.v1' and jsonb_typeof(value) = 'object';
end $$;
commit;

-- 2-가. 삭제 확인 — 모두 0 이어야 합니다
select (select count(*) from public.app_store where value::text like '%[PROD]%'
          or (key like 'gwPartner%' and value::text ~ '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)')) as app_store_남은_곳,
       (select count(*) from public.customers where id in ('c1018','c1019','c1020','c1021','c1022')) as 업체_남은_수;


-- =========================== 3단계: 되돌리기 (문제가 있을 때만) ===========================
-- 아래 주석(/* */)을 풀고 실행하면 백업한 줄을 그대로 돌려놓습니다.
/*
begin;
do $$
declare t text; cols text;
begin
    for t in select distinct tbl from public.zz_backup_prod_test_20261123 where tbl <> 'app_store' loop
        -- 자동 계산 칸(예: customers.name)은 넣을 수 없어 빼고 넣습니다
        select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into cols
          from information_schema.columns
         where table_schema = 'public' and table_name = t and is_generated = 'NEVER' and identity_generation is distinct from 'ALWAYS';
        execute format('insert into public.%I (%s) select %s from public.zz_backup_prod_test_20261123 b, jsonb_populate_record(null::public.%I, b.row_data) r where b.tbl = %L on conflict do nothing',
                       t, cols, (select string_agg('r.' || c, ', ') from unnest(string_to_array(cols, ', ')) c), t, t);
    end loop;
    update public.app_store a
       set value = (b.row_data->'value'), updated_at = now()
      from public.zz_backup_prod_test_20261123 b
     where b.tbl = 'app_store' and a.key = b.row_data->>'key';
end $$;
commit;
*/
-- 화면에서 이상 없음을 확인한 뒤(1~2주) 백업 표를 지웁니다:  drop table public.zz_backup_prod_test_20261123;
