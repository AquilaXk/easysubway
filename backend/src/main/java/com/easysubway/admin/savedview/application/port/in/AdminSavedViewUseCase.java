package com.easysubway.admin.savedview.application.port.in;

import com.easysubway.admin.savedview.domain.AdminSavedView;
import java.util.List;

public interface AdminSavedViewUseCase {

	/** 이름 기준 upsert: 같은 (소유자·화면·이름)이 있으면 질의를 갱신, 없으면 생성. */
	AdminSavedView saveView(SaveAdminSavedViewCommand command);

	List<AdminSavedView> listViews(String adminLoginId, String programId);

	/** 소유자 확인 후 해당 뷰를 화면의 기본 뷰로 지정(기존 기본은 해제). */
	AdminSavedView setDefaultView(String adminLoginId, String viewId);

	/** 소유자 확인 후 삭제. */
	AdminSavedView deleteView(String adminLoginId, String viewId);
}
