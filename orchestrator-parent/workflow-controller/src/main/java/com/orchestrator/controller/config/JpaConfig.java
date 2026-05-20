package com.orchestrator.controller.config;

import com.zaxxer.hikari.HikariDataSource;
import jakarta.persistence.EntityManagerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.EnableTransactionManagement;

import javax.sql.DataSource;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

@Configuration
@EnableJpaRepositories(basePackages = "com.orchestrator.controller.repository")
@EnableTransactionManagement
public class JpaConfig {

    @Value("${DB_SHARD_A_URL:jdbc:postgresql://postgres-shard-a-svc:5432/orchestrator}")
    private String shardAUrl;

    @Value("${DB_SHARD_B_URL:jdbc:postgresql://postgres-shard-b-svc:5432/orchestrator}")
    private String shardBUrl;

    @Value("${DB_USER:admin}")
    private String dbUser;

    @Value("${DB_PASSWORD:admin123}")
    private String dbPassword;

    @Bean
    @Primary
    public DataSource routingDataSource() {
        DataSource shardA = createDataSource(shardAUrl, dbUser, dbPassword);
        DataSource shardB = createDataSource(shardBUrl, dbUser, dbPassword);
        ShardRoutingDataSource routing = new ShardRoutingDataSource();
        Map<Object, Object> targetDataSources = new HashMap<>();
        targetDataSources.put("shard-a", shardA);
        targetDataSources.put("shard-b", shardB);
        routing.setTargetDataSources(targetDataSources);
        routing.setDefaultTargetDataSource(shardA);
        routing.afterPropertiesSet();
        return routing;
    }

    @Bean
    @Primary
    public LocalContainerEntityManagerFactoryBean entityManagerFactory(DataSource routingDataSource) {
        LocalContainerEntityManagerFactoryBean em = new LocalContainerEntityManagerFactoryBean();
        em.setDataSource(routingDataSource);
        em.setPackagesToScan("com.orchestrator.controller.model");
        HibernateJpaVendorAdapter vendorAdapter = new HibernateJpaVendorAdapter();
        vendorAdapter.setDatabasePlatform("org.hibernate.dialect.PostgreSQLDialect");
        em.setJpaVendorAdapter(vendorAdapter);
        Properties jpaProperties = new Properties();
        jpaProperties.setProperty("hibernate.hbm2ddl.auto", "none");
        em.setJpaProperties(jpaProperties);
        return em;
    }

    @Bean
    @Primary
    public PlatformTransactionManager transactionManager(EntityManagerFactory entityManagerFactory) {
        return new JpaTransactionManager(entityManagerFactory);
    }

    private static HikariDataSource createDataSource(String url, String username, String password) {
        HikariDataSource dataSource = new HikariDataSource();
        dataSource.setJdbcUrl(url);
        dataSource.setUsername(username);
        dataSource.setPassword(password);
        dataSource.setDriverClassName("org.postgresql.Driver");
        return dataSource;
    }
}
