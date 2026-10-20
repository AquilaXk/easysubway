import { existsSync } from "node:fs";

// gh를 PATH 탐색에 맡기면 PATH 앞쪽의 쓰기 가능한 디렉터리에 놓인 실행 파일이 대신 실행될 수 있다.
// 그래서 패키지 관리자가 설치하는 고정 절대 경로(Ubuntu runner, 수동 설치, macOS Homebrew)에서만 찾고,
// 없으면 bare "gh"로 되돌아가지 않고 null을 돌려 호출자가 명시적 오류로 처리하게 한다.
export const GH_EXECUTABLE_CANDIDATES = ["/usr/bin/gh", "/usr/local/bin/gh", "/opt/homebrew/bin/gh"];

export function resolveGhExecutable(exists = existsSync) {
  return GH_EXECUTABLE_CANDIDATES.find((candidate) => exists(candidate)) ?? null;
}
