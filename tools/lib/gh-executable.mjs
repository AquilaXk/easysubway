import { existsSync } from "node:fs";
import { isAbsolute } from "node:path";

// gh를 PATH 탐색에 맡기면 PATH 앞쪽의 쓰기 가능한 디렉터리에 놓인 실행 파일이 대신 실행될 수 있다.
// 그래서 패키지 관리자가 설치하는 고정 절대 경로(Ubuntu runner, 수동 설치, macOS Homebrew)에서만 찾고,
// 없으면 bare "gh"로 되돌아가지 않고 null을 돌려 호출자가 명시적 오류로 처리하게 한다.
export const GH_EXECUTABLE_CANDIDATES = ["/usr/bin/gh", "/usr/local/bin/gh", "/opt/homebrew/bin/gh"];

// 테스트가 기본 provider 경로까지 가짜 gh로 보내 "실제 gh 호출 0건"을 단언할 수 있게 하는 이음새다.
// node:test 러너가 자식 프로세스에 설정하는 NODE_TEST_CONTEXT가 있을 때만 읽고, 절대 경로가 아니면 무시한다.
// 운영 실행(`node tools/...`)에는 NODE_TEST_CONTEXT가 없으므로 이 변수는 효과가 없다.
export const TEST_GH_EXECUTABLE_ENV = "EASYSUBWAY_TEST_ONLY_GH_EXECUTABLE";

export function resolveGhExecutable({ exists = existsSync, env = process.env } = {}) {
  const testOverride = env.NODE_TEST_CONTEXT ? env[TEST_GH_EXECUTABLE_ENV] : undefined;
  if (typeof testOverride === "string" && isAbsolute(testOverride)) return testOverride;
  return GH_EXECUTABLE_CANDIDATES.find((candidate) => exists(candidate)) ?? null;
}
