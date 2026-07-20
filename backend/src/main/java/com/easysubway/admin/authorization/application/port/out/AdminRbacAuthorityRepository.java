package com.easysubway.admin.authorization.application.port.out;

import com.easysubway.admin.authorization.AdminRbacRole;
import java.util.Set;

public interface AdminRbacAuthorityRepository {

	Set<String> findPermissionAuthorities(String loginId);

	/**
	 * env로 지정된 관리자 계정이 부팅 시점에 지정 RBAC role을 반드시 보유하도록 보증한다.
	 * 이미 동일한 role 할당이 있으면 아무 것도 하지 않으며(멱등), 로그인 ID는 저장소에
	 * 하드코딩하지 않고 호출 시점에 전달받은 값만 사용한다. 기본 구현은 no-op이라
	 * 이 port를 단일 조회 함수로 소비하는 경로(테스트 람다 등)는 영향받지 않는다.
	 */
	default void seedRole(String loginId, AdminRbacRole role) {
	}
}
