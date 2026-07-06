package com.easysubway.route.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.route.application.port.out.LoadRouteTimetablePort;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * 출시게이트 스위치(@ConditionalOnProperty) 회귀 검증: flag 미설정/false면 로더 빈이 아예 없어야 하고
 * flag=true일 때만 등록된다. @Profile 게이트는 관례(리포지토리 ~15곳 동일)로 별도.
 */
class TimetableSeedLoaderConditionTest {

	// prod-like 프로파일을 활성화해 @Profile 게이트를 만족시키고 @ConditionalOnProperty(flag)만 변수로 둔다.
	private final ApplicationContextRunner runner = new ApplicationContextRunner()
		.withInitializer(context -> context.getEnvironment().setActiveProfiles("prod-like"))
		.withBean(LoadRouteTimetablePort.class, () -> LoadRouteTimetablePort.RouteTimetable::empty)
		.withBean(javax.sql.DataSource.class,
			() -> new DriverManagerDataSource("jdbc:h2:mem:seed-cond;DB_CLOSE_DELAY=-1", "sa", ""))
		.withBean(PlatformTransactionManager.class,
			() -> new DataSourceTransactionManager(
				new DriverManagerDataSource("jdbc:h2:mem:seed-cond;DB_CLOSE_DELAY=-1", "sa", "")))
		.withUserConfiguration(TimetableSeedLoader.class);

	@Test
	void loaderAbsentWhenFlagMissing() {
		runner.run(context -> assertThat(context).doesNotHaveBean(TimetableSeedLoader.class));
	}

	@Test
	void loaderAbsentWhenFlagFalse() {
		runner.withPropertyValues("easysubway.timetable.seed.enabled=false")
			.run(context -> assertThat(context).doesNotHaveBean(TimetableSeedLoader.class));
	}

	@Test
	void loaderPresentWhenFlagTrue() {
		runner.withPropertyValues("easysubway.timetable.seed.enabled=true")
			.run(context -> assertThat(context).hasSingleBean(TimetableSeedLoader.class));
	}
}
