-- ============================================================================
-- [운영] [PROD] 시험 자료 찾기 — 조회 전용 (2026-11-23)
-- 다니엘님 "운영에 데이터 중 [PROD]로 등록된 것들 초반 테스트용 데이터를 모두 찾아서 삭제"
--
-- 이 파일은 아무것도 바꾸지 않습니다 (SELECT 만). Supabase 운영 프로젝트 › SQL Editor 에서
-- 아래 ①, ②, ③ 을 하나씩 실행하고 결과를 Claude 에게 붙여 주세요.
-- 결과를 보고 표마다 정확히 어떤 줄을 지울지 정한 삭제 SQL(백업 포함)을 따로 만듭니다.
-- 운영 DB 실행은 관리자(다니엘님)만 합니다.
-- ============================================================================

-- ① 표마다 [PROD] 가 들어간 줄 수 — 0 보다 큰 표만 보입니다
select table_name as 표,
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from public.%I t where t::text like %L',
                                  table_name, '%[PROD]%'), false, true, '')))[1]::text::int as 줄_수
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE'
order by 2 desc nulls last;
-- (결과에서 줄_수 가 0 인 표는 무시하셔도 됩니다)

-- ② 그 줄들의 앞부분 (표마다 최대 50줄, 한 줄당 앞 300자) — 무엇을 지울지 확인용
select table_name as 표,
       (xpath('/row/j/text()',
              query_to_xml(format('select coalesce(json_agg(x), ''[]'') as j from (select left(t::text, 300) as x from public.%I t where t::text like %L limit 50) s',
                                  table_name, '%[PROD]%'), false, true, '')))[1]::text as 내용
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE'
  and (xpath('/row/c/text()',
             query_to_xml(format('select count(*) as c from public.%I t where t::text like %L',
                                 table_name, '%[PROD]%'), false, true, '')))[1]::text::int > 0;

-- ③ app_store(한 줄에 목록째 저장되는 설정 · 인바운드 등) — 키별로 [PROD] 가 몇 번 나오는지
--    여기 나온 키는 줄을 통째로 지우면 안 되고, 목록 안의 [PROD] 항목만 빼야 합니다.
select key as 키,
       (select count(*) from regexp_matches(value::text, '\[PROD\]', 'g')) as 나온_횟수,
       length(value::text) as 전체_길이,
       updated_at as 마지막_저장
from public.app_store
where value::text like '%[PROD]%'
order by 2 desc;

-- ④ 파트너센터 아이디 전체 목록 — 아이디에는 '[PROD]' 글자가 없어 ①~③ 에 나오지 않습니다.
--    이 목록에서 시험용 아이디를 골라 알려 주시면 그것만 빼는 SQL 을 만듭니다.
select a->>'loginId'   as 아이디,
       c.name          as 업체명,
       a->>'partnerId' as 업체_id,
       a->>'manager'   as 담당자,
       a->>'active'    as 사용,
       a->>'createdAt' as 만든_날,
       a->>'createdBy' as 만든_사람,
       a->>'memo'      as 메모,
       (c.name like '%[PROD]%') as 업체명에_PROD
from public.app_store s
cross join lateral jsonb_array_elements(s.value) a
left join public.customers c on c.id = a->>'partnerId'
where s.key = 'gwPartnerAccounts.v1'
order by a->>'createdAt', a->>'loginId';

-- ⑤ [PROD] 업체 5곳(c1018~c1022) · 파트너 아이디 5개(ptn00001~00005)에 연결된 자료 — 이름에 [PROD] 가 없어도 번호로 찾습니다
--    (예: 그 업체의 업무 · 계약 · 출금예정 · 첨부 · 파트너 권한 · 로그인 기록)
--    ⑤-1 표마다 줄 수
select table_name as 표,
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from public.%I t where t::text ~ %L',
                                  table_name, '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)'), false, true, '')))[1]::text::int as 줄_수
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE'
order by 2 desc nulls last;
--    ⑤-2 app_store 키마다 나온 횟수
select key as 키,
       (select count(*) from regexp_matches(value::text, '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)', 'g')) as 나온_횟수,
       length(value::text) as 전체_길이
from public.app_store
where value::text ~ '(^|[^A-Za-z0-9])(c10(1[89]|2[012])|ptn0000[1-5])([^0-9]|$)'
order by 2 desc;
