/**
 * 실행 환경 설정 — 운영(prod) (2026-10-12)
 *
 * 개발환경(config/app-config.js · env 'dev')과 이 파일만 다릅니다.
 *   · env               'prod' — 홈 화면 이름에 [DEV] 가 붙지 않습니다
 *   · supabaseUrl       운영 Supabase 프로젝트
 *   · supabaseAnonKey   운영 프로젝트의 Publishable(anon) 키 — 브라우저에 노출되는 공개 키입니다. RLS 로 보호합니다.
 *                       ※ 비어 있으면 로컬 저장소 모드로 돌아 자료가 브라우저에만 남습니다 — 반드시 채운 뒤 배포합니다.
 * 이 파일에 secret(service_role) 키를 **절대** 넣지 마세요 (그 키는 Cloudflare Worker 환경변수에만).
 */
window.KOB_CONFIG = {
    env: 'prod',
    supabaseUrl: 'https://qlrpokxghtvbaxsnwhno.supabase.co',
    supabaseAnonKey: '',   // TODO: 운영 Supabase › Project Settings › API Keys › Publishable key (sb_publishable_…)
    apiBase: ''
};
